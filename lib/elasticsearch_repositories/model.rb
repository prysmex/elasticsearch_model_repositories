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
          strategy.reload_indices_iterator(start_time, end_time) do |import_db_query, iterator_options|
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
      # @param [Boolean] refresh
      # @param [Boolean] verify_count
      #
      # @return [Hash] total errors by strategy
      def reload_indices(
        start_time: nil,
        end_time: nil,
        **override_options,
        &block
      )

        # defaults
        override_options.reverse_merge!(
          refresh: true,
          verify_count: false
        )

        # call reload_indices_iterator for all strategies
        indexing_strategies.each_with_object({}) do |strategy, return_hash|
          key = strategy.class.name
          current_hash = return_hash[key] = []

          strategy.reload_indices_iterator(start_time, end_time) do |import_db_query, iterator_options|

            # merge passed options
            options = iterator_options.deep_merge(override_options)

            options[:find_in_batches_params] ||= {}
            options[:find_in_batches_params][:query] = -> { strategy.reindexing_includes_proc.call(import_db_query) }
    
            # ensure important options are present before recreating index
            %i[index settings mappings].each do |name|
              next unless options[name].nil?
              raise ArgumentError.new("missing option #{name} while importing")
            end
            
            import_return = import(strategy: strategy, **options, &block)

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

      # @example
      #
      #   with_timer do |ruler|
      #     ruler.call(:foo) do
      #       sleep(1)
      #     end
      
      #     ruler.call(:foo) do
      #       sleep(2)
      #     end
      #   end
      #
      #   => {:foo=>[1.001047, 2.001069]}
      #
      # @param [Boolean] average
      # @return [Hash{* => Array<Integer>}]
      def with_timer(average: false)
        obj = {}
        wrapper = lambda do |key, normalizer = nil, &block|
          key_array = obj[key] ||= []
      
          now = Time.now
          value = block.call
          took = Time.now - now
          took = normalizer.call(took) if normalizer
          key_array.push(took)
          [value, took]
        end
        yield wrapper, obj
        obj = obj.transform_values! {|v| v.sum(0.0) / v.size } if average
        obj
      end

      # Temporarily sets a value for 'refresh_interval' setting
      #
      # @param [BaseStrategy] strategy
      # @param [String] index
      # @param [String] interval
      # @return [void]
      def with_refresh_interval(strategy, index, interval)
        return if interval == false

        current_interval = strategy
          .client
          .indices
          .get_settings(index: index)
          .dig(index, 'settings', 'index', 'refresh_interval') || '1s'

        strategy.client.indices.put_settings(
          body: { index: { refresh_interval: interval } },
          index: index
        )

        yield
      ensure
        # restore refresh_interval
        strategy.client.indices.put_settings(
          body: { index: { refresh_interval: current_interval } },
          index: index
        )
      end

      # @param index [String]
      # @param mappings [Hash]
      # @param settings [Hash]
      # @param strategy   [ElasticsearchRepositories::BaseStrategy]
      # @param find_in_batches_params [Hash]
      # @param create_index_params [Hash]
      # @param bulk_request_params [Hash]
      # @param refresh_interval   [String|NilClass]
      # @param batch_sleep   [Integer]
      # @param bulkify   [Proc]
      # @param force   [Boolean]
      #
      # @return [Hash]
      def import(
        index:,
        mappings:,
        settings:,
        strategy:,
        find_in_batches_params: {},
        create_index_params: {},
        bulk_request_params: {},
        refresh_interval: '-1',
        batch_sleep: 2,
        bulkify: nil,
        force: nil,
        **_kwargs # allow passing unknown options
      )
        adapter_importing_module = Adapter.new(self).importing_mixin
        bulkify ||= adapter_importing_module::BULKIFY_PROC

        # compatibility
        unless force.nil?
          create_index_params[:force] = force
        end
  
        # create/recreate index
        strategy.create_index(
          index: index,
          mappings: mappings,
          settings: settings,
          **create_index_params
        )

        return_hash = { errors: 0, total: 0 }

        # call adapter find_in_batches
        measurements = with_refresh_interval(strategy, index, refresh_interval) do
          with_timer(average: true) do |timer, timer_data|
            adapter_importing_module.find_in_batches(self, **find_in_batches_params) do |batch|
              batch_size = batch.size
              normalizer = ->(took) { batch_size.fdiv(took) }

              # time __batch_to_bulk
              bulk, _ = timer.call(:bulkify_per_s, normalizer) do
                __batch_to_bulk(batch, strategy, bulkify)
              end

              # time bulk request
              response, _ = timer.call(:bulk_req_per_s, normalizer) do
                strategy.client.bulk({
                  index: index,
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
  
      # Maps an array of the model's instances by calling the bulkify Proc
      #
      # @param [Array] batch
      # @param [ElasticsearchRepositories::BaseStrategy] strategy
      # @param [Proc] bulkify
      def __batch_to_bulk(batch, strategy, bulkify)
        batch.map { |model| bulkify.call(model, strategy) }
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
              index: index
            })['count']

        if db_count != es_count
          puts "MISMATCH! -> (DB=#{db_count}, ES=#{es_count}) for query: #{verify_count_query}"
        else
          puts "(DB=#{db_count}, ES=#{es_count}) for query: #{verify_count_query}"
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
      def register_strategy(strategy_klass, name='main', &block)
        self.indexing_strategies ||= []

        # raise error for diplicate name
        if get_strategy(name)
          raise StandardError.new("deplicate strategy name '#{name}' on model #{self.name}")
        end

        strategy = strategy_klass.new(self, ::ElasticsearchRepositories.client, name, &block)
        indexing_strategies.push(strategy)

        # add class to registry unless already registered
        if self.is_a?(Class) && !::ElasticsearchRepositories::ClassRegistry.all.map(&:to_s).include?(self.name)
          ::ElasticsearchRepositories::ClassRegistry.add(self)
        end
      end

      # Update an indexing strategy by name
      #
      # @param [String] name the identifier of the strategy
      # @return [void]
      def update_strategy(name, &block)
        strategy = get_strategy(name)
        if !strategy
          raise StandardError.new("strategy '#{name}' not found on model #{self.name}")
        end

        strategy.update(&block)
      end

      # @param [String] name
      # @return [NilClass|BaseStrategy]
      def get_strategy(name)
        indexing_strategies&.find{|s| s.name == name }
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
        self.name.underscore.dasherize.pluralize
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
          index_with_strategy(action, strategy, &block)
        end
      end

      # Indexes the record with one strategy
      #
      # @param [String] action
      # @param [String|BaseStrategy] strategy, name or instance
      # @return [void]
      def index_with_strategy(action = 'create', strategy, &block)
        strategy = self.class.get_strategy(strategy) unless strategy.is_a? BaseStrategy

        strategy.index_record_to_es(action, self, &block)
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
      def index_document(strategy, action, **options)
        raise NotImplementedError('need to implement own index_document method')
      end

    end

    extend ClassMethods
    include InstanceMethods

  end

end