# frozen_string_literal: true

module ElasticsearchRepositories

  #
  # Contains all the modules needed to be included in a *Model*
  #
  module Model

    module Importing

      # Creates indices for a model's strategies
      # If the indices are timebased, you may pass start_time and end_time to only
      # create a subset of indices
      #
      # @param [DateTime] start_time start_time passed to reload_indices_iterator
      # @param [DateTime] end_time end_time passed to reload_indices_iterator
      # @return [void]
      def create_indices(start_time: nil, end_time: nil, **kwargs)
        indexing_strategies.each do |strategy|
          strategy.reload_indices_iterator(start_time, end_time) do |_import_db_query, iterator_options|
            strategy.create_index(
              iterator_options.slice(:index, :mappings, :settings).merge!(kwargs)
            )
          end
        end
      end

      # Reloads data into a model's indices
      #
      # @param [DateTime] start_time used for reload_indices_iterator
      # @param [DateTime] end_time used for reload_indices_iterator
      # @param [Proc] each_batch_proc
      # @param [Proc] each_index_proc
      # @param [Boolean] refresh
      # @param [Boolean] verify_count
      # @param [String|NilClass|FalseClass] tmp_refresh_interval
      # @param [String|NilClass] refresh_interval
      # @param [Hash] find_in_batches_params
      # @param [Hash] create_index_params
      # @param [Boolean] force
      # @param [Hash] bulk_request_params
      # @param [Integer] batch_sleep
      # ---private
      # @param [Boolean] verify_count_query
      # @param [String] index
      # @param [] settings
      # @param [] mappings
      # @param [Proc] bulkify
      #
      # @return [Hash] total errors by strategy
      def reload_indices(
        start_time: nil,
        end_time: nil,
        each_batch_proc: nil,
        strategy_names: nil,
        ignore_reindex_process_query: false,
        **override_options
      )
        # defaults
        override_options.reverse_merge!(
          refresh: true,
          verify_count: false
        )

        required_options = %i[index settings mappings]

        # call reload_indices_iterator for all strategies
        indexing_strategies.each_with_object({}) do |strategy, return_hash|
          next if strategy_names && !strategy_names.include?(strategy.name)

          key = strategy.class.name
          current_hash = return_hash[key] = []

          strategy.reload_indices_iterator(start_time, end_time) do |import_db_query, iterator_options|
            # merge passed options
            options = iterator_options.deep_merge(override_options)

            # ensure important options are present before recreating index
            required_options.each do |name|
              next unless options[name].nil?

              raise ArgumentError.new("missing option #{name} while importing")
            end

            options[:each_index_proc]&.call(options)

            # NOTE: reindex_process_query and process_query achieve the same function, but reindex_process_query is
            # designed to be defined in the strategy and process_query to be passed in a specific context.

            # allow to process query while reindexing
            import_db_query = options[:process_query].call(import_db_query) if options[:process_query]

            # find_in_batches_params
            options[:find_in_batches_params] ||= {}
            options[:find_in_batches_params][:query] = if ignore_reindex_process_query
              -> { import_db_query }
            else
              -> { strategy.reindex_process_query.call(import_db_query) }
            end

            # create_index_params
            options[:create_index_params] ||= {}
            options[:create_index_params][:force] = options[:force] unless options[:force].nil?

            # create/recreate index
            strategy.create_index(
              index: options[:index],
              mappings: options[:mappings],
              settings: options[:settings],
              **options[:create_index_params]
            )

            import_return = if block_given?
              yield(self, strategy, options)
            else
              import(strategy:, **options, &each_batch_proc)
            end

            current_hash.push(import_return)
            strategy.refresh_index index: options[:index] if options[:refresh]

            if options[:verify_count] && options[:verify_count_query]
              unless options[:refresh]
                strategy.client.transport.logger&.debug('verify_count may be inconcistent when refresh is false')
              end
              verify_index_doc_count(strategy, import_db_query, options[:index], options[:verify_count_query])
            end
          end
        end
      end

      private

      # @param [String] index
      # @param [ElasticsearchRepositories::BaseStrategy] strategy
      # @param [Hash] find_in_batches_params
      # @param [Hash] bulk_request_params
      # @param [String|NilClass|FalseClass] tmp_refresh_interval
      # @param [String|NilClass] refresh_interval
      # @param [Integer] batch_sleep
      # @param [Proc] bulkify
      #
      # @return [Hash]
      def import(
        index:,
        strategy:,
        find_in_batches_params: {},
        bulk_request_params: {},
        tmp_refresh_interval: '-1',
        batch_sleep: 2,
        bulkify: nil,
        **kwargs # allow passing unknown kwargs
      )
        return_hash = { errors: 0, total: 0 }

        adapter_importing_module = Adapter.new(self).importing_mixin
        bulkify ||= adapter_importing_module::BULKIFY_PROC

        # call adapter find_in_batches
        measurements = ElasticsearchRepositories.with_refresh_interval(
          strategy,
          index,
          tmp_refresh_interval,
          **kwargs # pass refresh_interval
        ) do
          ElasticsearchRepositories.with_timer(average: true) do |timer, timer_data|
            adapter_importing_module.find_in_batches(self, **find_in_batches_params) do |batch|
              batch_size = batch.size
              normalizer = ->(took) { batch_size.fdiv(took) }

              # time bulkify
              bulk, _took = timer.call(:bulkify_per_s, normalizer) do
                batch.map { |r| bulkify.call(r, strategy) }
              end

              # time bulk request
              response, _took = timer.call(:bulk_req_per_s, normalizer) do
                strategy.client.bulk({
                  index:,
                  body: bulk
                }.merge!(bulk_request_params))
              end

              # register response took
              timer_data[:indexing_speed_per_s] ||= []
              timer_data[:indexing_speed_per_s].push(
                normalizer.call(response['took'] / 1000.0)
              )

              # get items with errors
              error_items = response['items'].select { |item| item.values.first['error'] }

              # increment errors
              return_hash[:errors] += error_items.size

              # increment total
              return_hash[:total] += batch_size

              yield(strategy, response, error_items, timer_data) if block_given?

              sleep(batch_sleep) if batch_sleep
            end
          end
        end

        return_hash.merge!(measurements)
      end

      # verifies that an index contains the same amount of
      # documents as the database for a specific db and es query.
      #
      # @param [ElasticsearchRepositories::BaseStrategy] strategy
      # @param [ActiveRecord_Relation] import_db_query
      # @param [String] index
      # @param [Hash] verify_count_query
      # @return [Boolean]
      def verify_index_doc_count(strategy, import_db_query, index, verify_count_query)
        db_count = import_db_query.count

        es_count = strategy
          .client
          .count({
            body: verify_count_query,
            index:
          })['count']

        if db_count == es_count
          puts "(DB=#{db_count}, ES=#{es_count}) for query: #{verify_count_query}"
        else
          puts "MISMATCH! -> (DB=#{db_count}, ES=#{es_count}) for query: #{verify_count_query}"
        end

        db_count == es_count
      end

    end

    module ClassMethods

      include Importing

      attr_accessor :indexing_strategies

      # Registers a new indexing strategy to the model
      # Name paramter is used if updating the strategy later on is desired
      #
      # @param [BaseStrategy] strategy_klass
      # @param [String] name the identifier of the strategy, can be used if updating the strategy later on is desired
      # @return [void]
      def register_strategy(strategy_klass, name = 'main', &)
        self.indexing_strategies ||= []

        # raise error for diplicate name
        raise StandardError.new("deplicate strategy name '#{name}' on model #{self.name}") if get_strategy(name)

        strategy = strategy_klass.new(self, ::ElasticsearchRepositories.client, name, &)
        indexing_strategies.push(strategy)

        # add class to registry unless already registered
        return unless is_a?(Class) && !::ElasticsearchRepositories::ClassRegistry.all.map(&:to_s).include?(self.name)

        ::ElasticsearchRepositories::ClassRegistry.add(self)
      end

      # Update an indexing strategy by name
      #
      # @param [String] name the identifier of the strategy
      # @return [void]
      def update_strategy(name, &)
        strategy = get_strategy(name)
        raise StandardError.new("strategy '#{name}' not found on model #{self.name}") unless strategy

        strategy.update(&)
      end

      # @param [String] name
      # @return [NilClass|BaseStrategy]
      def get_strategy(name)
        indexing_strategies&.find { |s| s.name == name }
      end

      # Returns the first strategy (for now)
      #
      # @return [BaseStrategy]
      def default_indexing_strategy
        self.indexing_strategies.first
      end

      # defines how a model's name is embedded in an index name
      #
      # @example
      #   SomeModel => some-model
      #
      # @return [String]
      def _to_index_model_name
        name.underscore.dasherize.pluralize
      end

      # this base name is a contract to be followed by each class
      #
      # @todo this is Rails specific
      #
      # @return [String]
      def _base_index_name
        _to_index_model_name
      end

      # Gets all possible indices for all strategies implemented on the class
      #
      # @return [Array<String>]
      def all_klass_indices(*args, **kwargs)
        indexing_strategies.each_with_object([]) do |strategy, obj|
          strategy.all_indices(*args, **kwargs).each do |index|
            obj.push(index)
          end
        end
      end

    end

    module InstanceMethods

      # Indexes the record to all of it's classes strategies
      #
      # @param [String] action
      # @return [void]
      def index_with_all_strategies(action = 'create', &block)
        self.class.indexing_strategies.each do |strategy|
          index_with_strategy(strategy, action, &block)
        end
      end

      # Indexes the record with one strategy
      #
      # @param [String] action
      # @param [String|BaseStrategy] strategy, name or instance
      # @return [void]
      def index_with_strategy(strategy, action = 'create', &)
        strategy = self.class.get_strategy(strategy) unless strategy.is_a? BaseStrategy

        strategy.index_record_to_es(action, self, &)
      end

      private

      # Override this method on your model to handle indexing
      #
      # @param [ElasticsearchRepositories::BaseStrategy] strategy
      # @param [String] action
      # @option options [Hash] mappings
      # @option options [Hash] settings
      # @option options [Integer,String] id
      # @option options [Boolean] index_without_id
      # @option options [String] options
      #   @option options [Integer,String] id
      #   @option options [Hash] body
      #   @option options [String] index
      # @return [void]
      def index_document(_strategy, _action, **_options)
        raise NotImplementedError('need to implement own index_document method')
      end

    end

    extend ClassMethods
    include InstanceMethods

  end

end