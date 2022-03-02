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
      # @param [DateTime] start_time start_time passed to reindexing_index_iterator
      # @param [DateTime] end_time end_time passed to reindexing_index_iterator
      # @param [Boolean] force
      # @return [void]
      def create_indices!(start_time: nil, end_time: nil, force: true)
        indexing_strategies.each do |strategy|
          strategy.reindexing_index_iterator(start_time, end_time) do |import_db_query, iterator_options|
            strategy.create_index({
              force: force,
              index: iterator_options[:index],
              mappings: iterator_options[:mappings],
              settings: iterator_options[:settings]
            })
          end
        end
      end

      # Reloads data into a model's indices
      # 
      # By default it recreates the indices, if you want to only load data use `force: false` option
      #  
      # @param [DateTime] start_time start_time passed to reindexing_index_iterator
      # @param [DateTime] end_time end_time passed to reindexing_index_iterator
      # @param [Hash] find_params
      # @param [Integer] batch_sleep
      # @param [Boolean] refresh
      # @param [Boolean] force
      # @param [Boolean] verify_count
      # @return [Hash] total errors by strategy
      def reload_indices!( start_time: nil, end_time: nil, find_params: { batch_size: 1000 }, batch_sleep: 2, force: true, refresh: false, verify_count: true, &block )
  
        override_options = {
          find_params: find_params,
          batch_sleep: batch_sleep,
          force: force,
          refresh: refresh,
          verify_count: verify_count,
        }

        # call reindexing_index_iterator for all strategies
        indexing_strategies.each_with_object({}) do |strategy, return_hash|
          key = strategy.class.name
          return_hash[key] = []
          strategy.reindexing_index_iterator(start_time, end_time) do |import_db_query, iterator_options|

            # extract allowed options from iterator
            iterator_options = iterator_options.slice(
              :find_params,
              :batch_sleep,
              :verify_count_query,
              :force,
              # :import_db_query
              :index,
              :index_without_id,
              :mappings,
              :request_params,
              :refresh,
              :settings,
              :strategy,
              :bulkify,
              :verify_count
            )

            # merge final options
            merged_options = iterator_options.merge(override_options)
    
            # ensure important options are present before recreating index
            [ :index, :strategy, :settings, :mappings ].each do |name|
              if merged_options[name].nil?
                raise ArgumentError.new("missing option #{name} while importing")
              end
            end
            
            strategy = merged_options[:strategy]
            value = with_refresh_interval(strategy, merged_options[:index], -1) do
              import(
                query: -> {
                  strategy.reindexing_includes_proc.call(import_db_query)
                },
                **merged_options.slice(:force, :index, :find_params, :refresh, :scope, :strategy, :bulkify),
                &block
              )
            end

            return_hash[key].push(value)

            if merged_options[:verify_count] && merged_options[:verify_count_query]
              verify_index_doc_count(import_db_query, merged_options)
            end

          end
        end
      end

      private

      # Temporarily sets a value for 'refresh_interval' setting
      #
      def with_refresh_interval(strategy, index, interval)
        current_settings = strategy.client.indices.get_settings(index: index)
        current_interval = current_settings.dig(index, 'settings', 'index', 'refresh_interval') || '1s'

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

      # @param [Hash] options
      # @param options[:refresh]   [Boolean]
      # @param options[:index]   [String]
      # @param options[:strategy]   [ElasticsearchRepositories::BaseStrategy]
      # @param options[:bulkify]   [Proc]
      # @param options[:request_params]   [Hash]
      # @param options[:return]   ['errors', 'count']
      # @param options[:force]   [Boolean]
      # @param options[:query]   [Proc]
      # @param options[:scope]   [Symbol]
      # @param options[:batch_sleep]   [Integer]
      # @return [Hash] errors and total count
      def import( refresh: false, index:, strategy:, bulkify: nil, request_params: {}, find_params: {}, **options, &block )
        adapter_importing_module = Adapter.new(self).importing_mixin
        bulkify ||= adapter_importing_module::BULKIFY_PROC
  
        if options[:force]
          strategy.create_index(
            **options.slice(:index, :force, :mappings, :settings)
          )
        elsif !strategy.index_exists? index: index
          raise ArgumentError,
                "#{index} does not exist to be imported into. Use create_index or the :force option to create it."
        end

        meta_hash = { errors: [], total: [], indexing_speed: [], batch_speed: [] }
        batch_start_at = Time.now

        # call adapter find_in_batches
        adapter_importing_module.find_in_batches(self, **options.slice(:query, :scope, :find_params)) do |batch|

          params = request_params.merge({
            index: index,
            body:  __batch_to_bulk(batch, strategy, bulkify)
          })
  
          response = strategy.client.bulk params

          # errors meta
          errors = response['items'].select { |k, v| k.values.first['error'] }
          meta_hash[:errors].push(errors.size)

          # total meta
          meta_hash[:total].push(batch.size)

          # speed
          items_size = response['items'].size
          indexing_speed = batch_speed = nil
          if items_size > 0
            # indexing
            if response['took'] > 0
              indexing_speed = (items_size.fdiv(response['took']) * 1000).round(0)
              meta_hash[:indexing_speed].push(indexing_speed)
            end
  
            # batch
            batch_speed = items_size.fdiv(Time.now - batch_start_at).round(0)
            meta_hash[:batch_speed].push(batch_speed)
          end

          yield(response, errors, indexing_speed, batch_speed) if block_given?
    
          if options[:batch_sleep] && options[:batch_sleep] > 0
            sleep options[:batch_sleep]
          end

          batch_start_at = Time.now
        end
  
        strategy.refresh_index index: index if refresh
        
        {
          errors: meta_hash[:errors].sum,
          total: meta_hash[:total].sum,
          indexing_speed: meta_hash[:indexing_speed].sum.to_f / [meta_hash[:indexing_speed].size, 1].max,
          batch_speed: meta_hash[:batch_speed].sum.to_f / [meta_hash[:batch_speed].size, 1].max
        }
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
      # @param [] import_db_query an active_record query relation
      # @param [Hash] options
      # @param options[:strategy]   [ElasticsearchRepositories::BaseStrategy]
      # @param options[:index]      [String]
      # @param options[:verify_count_query]   [Hash]
      # @return [Boolean]
      def verify_index_doc_count(import_db_query, options)
        index_name = options[:index]
        verify_count_query = options[:verify_count_query]
  
        db_count = import_db_query
            .count
        sleep(2)
        es_count = options[:strategy]
            .client
            .count({
              body: verify_count_query,
              index: index_name
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

        if self.is_a?(Class) && !::ElasticsearchRepositories::ClassRegistry.all.map(&:to_s).include?(self.name)
          ::ElasticsearchRepositories::ClassRegistry.add(self)
        end

        strategies = indexing_strategies || []
        strategy = strategies.find{|s| s.instance_variable_get('@name') == name }
        if strategy
          raise StandardError.new("deplicate strategy name '#{name}' on model #{self.name}")
        else
          strategy = strategy_klass.new(self, ::ElasticsearchRepositories.client, name, &block)
          strategies.push(strategy)
          self.instance_variable_set('@indexing_strategies', strategies)
        end
      end

      # Update an indexing strategy by name
      #
      # @param [String] name the identifier of the strategy
      # @return [void]
      def update_strategy(name, &block)
        strategies = indexing_strategies || []
        strategy = strategies.find{|s| s.instance_variable_get('@name') == name }
        if strategy
          strategy.update(&block)
        else
          raise StandardError.new("strategy '#{name}' not found on model #{self.name}")
        end
      end

      # Returns the fir strategy (for now)
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
      def all_klass_indices(*args)
        indexing_strategies.each_with_object([]) do |strategy, obj|
          strategy.reindexing_index_iterator(*args) do |import_db_query, iterator_options|
            obj.push(iterator_options[:index]) if iterator_options[:index]
          end
        end
      end

      # delete all indices for a class
      #
      # @return [void]
      def delete_all_klass_indices(*args)
        all_klass_indices(*args).each do |index|
          next unless ElasticsearchRepositories.client.indices.exists?(index: index)
          ElasticsearchRepositories.client.indices.delete(index: index)
        end
      end
      
    end

    module InstanceMethods

      # Indexes the record to all indices of it's classes strategies
      #
      # @return [void]
      def index_to_all_indices
        self.class.indexing_strategies.each do |strategy|
          strategy.index_record_to_es('create', self)
        end
      end
  
      # Override this method on your model to handle indexing
      #
      # @return [void]
      def _index_document(action, options)
        raise NotImplementedError('need to implement own _index_document method')
      end

    end

    extend ClassMethods
    include InstanceMethods

  end

end