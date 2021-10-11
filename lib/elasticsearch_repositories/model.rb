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
      # By default it recreates the indices, if you want to only load data use `force: true` option
      #  
      # @param [DateTime] start_time start_time passed to reindexing_index_iterator
      # @param [DateTime] end_time end_time passed to reindexing_index_iterator
      # @param [Hash] options
      # @param options[:batch_size] [Integer]
      # @param options[:batch_sleep] [Integer]
      # @param options[:refresh] [Boolean]
      # @param options[:force] [Boolean]
      # @param options[:verify_count] [Boolean]
      # @return [Integer] number of errors for all strategies
      def reload_indices!(start_time: nil, end_time: nil, **options)
  
        override_options = options.slice(
          :batch_size,
          :batch_sleep,
          :force,
          :refresh,
          :verify_count
        )
        
        default_options = {
          batch_size: 1000,
          batch_sleep: 2,
          force: true,
          refresh: false,
          verify_count: true
        }
  
        error_count = 0

        # call reindexing_index_iterator for all strategies
        indexing_strategies.each do |strategy|
          strategy.reindexing_index_iterator(start_time, end_time) do |import_db_query, iterator_options|

            # extract allowed options from iterator
            iterator_options = iterator_options.slice(
              :batch_size,
              :batch_sleep,
              :es_query,
              :force,
              # :import_db_query
              :index,
              :index_without_id,
              :mappings,
              :pipeline,
              :refresh,
              :refresh,
              :settings,
              :strategy,
              :transform,
              :type,
              :verify_count
            )

            # merge final options
            merged_options = default_options
                .merge(iterator_options)
                .merge(override_options)
    
            # ensure important options keys are present
            [
              :batch_size, :index, :es_query,
              :strategy, :settings, :mappings
            ].each do|name|
              unless merged_options.key?(name)
                raise ArgumentError.new("missing key #{name} in options while importing")
              end
            end
    
            error_count += create_index_and_import_data(import_db_query, merged_options)

            if merged_options[:verify_count]
              verify_index_doc_count(import_db_query, merged_options)
            end

          end
        end
  
        return error_count
      end

      private
  
      # Creates an index, and calls #import
      # When options[:force] is true, the index in deleted and recreated with
      # mappings and settings
      #
      # @param [] import_db_query an active_record query relation
      # @param [Hash] options
      # @param options[:strategy]   [ElasticsearchRepositories::BaseStrategy]
      # @param options[:index]      [string]
      # @param options[:force]      [Boolean]
      # @param options[:mappings]   [Hash]
      # @param options[:settings]   [Hash]
      # @param options[:batch_size] [Integer]
      # @param options[:refresh]    [Boolean]
      # @param options[:scope]      []
      # @param options[:transform]  [Proc]
      # @return [Integer] number of errors for all strategies
      def create_index_and_import_data(import_db_query, options)
        strategy = options[:strategy]
        index_name = options[:index]
  
        # this is required because import does not support settings
        # if force is true, the index in deleted and re-created
        strategy.create_index({
          force: options[:force],
          index: index_name,
          mappings: options[:mappings],
          settings: options[:settings]
        })
  
        # set refresh_interval to -1 to speed up indexing
        strategy.client.indices.put_settings(
          index: index_name,
          body: { index: { refresh_interval: -1 } }
        )
  
        import(
          force: false,
          index: index_name,
          batch_size: options[:batch_size],
          refresh: options[:refresh],
          scope: options[:scope], # for some reason it only works if the query is defined inside the 'query' lambda
          strategy: strategy,
          transform: options[:transform],
          query: -> {
            strategy.reindexing_includes_proc.call(import_db_query)
          }
        ) do |response|
            puts "#{(response['items'].size.to_f * 1000 / response['took']).round(0)}/s"
        end
      ensure
        # restore refresh_interval @todo restore to origina, not hardcoded 1s
        strategy.client.indices.put_settings(
          index: index_name,
          body: { index: { refresh_interval: '1s' } }
        )
      end
  
      # verifies that an index contains the same amount of
      # documents as the database for a specific db and es query.
      #
      # @param [] import_db_query an active_record query relation
      # @param [Hash] options
      # @param options[:strategy]   [ElasticsearchRepositories::BaseStrategy]
      # @param options[:index]      [String]
      # @param options[:es_query]   [Hash]
      # @return [Boolean]
      def verify_index_doc_count(import_db_query, options)
        index_name = options[:index]
        es_query = options[:es_query]
  
        db_count = import_db_query
            .count
        sleep(2)
        es_count = options[:strategy]
            .client
            .count({
              body: es_query,
              index: index_name
            })['count']
        if db_count != es_count
          puts "MISMATCH! -> (DB=#{db_count}, ES=#{es_count}) for query: #{es_query}"
        else
          puts "(DB=#{db_count}, ES=#{es_count}) for query: #{es_query}"
        end
        db_count == es_count
      end

      # @param [Hash] options
      # @param options[:refresh]   [Boolean]
      # @param options[:index]   [String]
      # @param options[:type]   [String]
      # @param options[:strategy]   [ElasticsearchRepositories::BaseStrategy]
      # @param options[:transform]   [Proc]
      # @param options[:pipeline]   []
      # @param options[:return]   ['errors', 'count']
      # @param options[:force]   [Boolean]
      # @param options[:query]   [Proc]
      # @param options[:scope]   [Symbol]
      # @param options[:preprocess]   [Symbol]
      # @param options[:batch_sleep]   [Integer]
      # @return [Integer] errors count
      def import(options={}, &block)
        adapter_importing_module = Adapter.new(self).importing_mixin

        errors       = []
        refresh      = options.delete(:refresh)   || false
        target_index = options.delete(:index)
        target_type  = options.delete(:type)
        strategy    = options.delete(:strategy)
        transform    = options.delete(:transform) || adapter_importing_module::TRANSFORM_PROC
        pipeline     = options.delete(:pipeline)
        return_value = options.delete(:return)    || 'count'
  
        unless transform.respond_to?(:call)
          raise ArgumentError,
                "Pass an object responding to `call` as the :transform option, #{transform.class} given"
        end
  
        if options.delete(:force)
          strategy.create_index force: true, index: target_index
        elsif !strategy.index_exists? index: target_index
          raise ArgumentError,
                "#{target_index} does not exist to be imported into. Use create_index or the :force option to create it."
        end

        adapter_importing_module.find_in_batches(self, options) do |batch|
          params = {
            index: target_index,
            type:  target_type,
            body:  __batch_to_bulk(batch, strategy, transform)
          }
  
          params[:pipeline] = pipeline if pipeline
  
          response = strategy.client.bulk params
  
          yield response if block_given?
  
          errors +=  response['items'].select { |k, v| k.values.first['error'] }
  
          if options[:batch_sleep] && options[:batch_sleep] > 0
            sleep options[:batch_sleep]
          end
        end
  
        strategy.refresh_index index: target_index if refresh
  
        case return_value
          when 'errors'
            errors
          else
            errors.size
        end
      end
  
      # Maps an array of the model's instances by calling the transform Proc
      #
      # @param [Array] batch
      # @param [ElasticsearchRepositories::BaseStrategy] strategy
      # @param [Proc] transform
      def __batch_to_bulk(batch, strategy, transform)
        batch.map { |model| transform.call(model, strategy) }
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