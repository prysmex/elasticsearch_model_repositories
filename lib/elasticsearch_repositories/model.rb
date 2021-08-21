module ElasticsearchRepositories

  #
  # Contains all the modules needed to be included in a *Model*
  #
  module Model

    module Importing

      # Calls reindexing_index_iterator for all of the class's strategies
      #
      # @return [void]
      def _call_reindex_iterators(*payload, &block)
        self.instance_variable_get('@indexing_strategies').each do |strategy|
          strategy.public_send(:reindexing_index_iterator, *payload, &block)
        end
      end
  
      def reload_indices!(options={})
  
        required_options = [
          :batch_size, :index, :es_query,# :es_query_options,
          :strategy, :settings, :mappings
        ]
  
        start_time = options[:start_time]
        end_time = options[:end_time]
  
        sanitized_options = options.slice(
          :batch_size,
          :batch_sleep,
          :refresh,
          :force,
          :verify_count
        )
        
        default_options = {
          batch_size: 1000,
          batch_sleep: 2,
          refresh: false,
          force: true,
          verify_count: true
        }
  
        error_count = 0
        _call_reindex_iterators(
          start_time,
          end_time
        ) do |import_db_query, iterator_options|
          iterator_options = iterator_options.slice(
            :batch_size,
            :batch_sleep,
            :refresh,
            :force,
            :verify_count,
            :refresh,
            :index,
            :type,
            :transform,
            :pipeline,
            # :import_db_query,
            :strategy,
            :index_without_id,
            :settings,
            :mappings,
            :es_query,
            :es_query_options
          )
          merged_options = default_options
              .merge(iterator_options)
              .merge(sanitized_options)
  
          required_options.each do|name|
            unless merged_options.key?(name)
              raise ArgumentError.new("missing key #{name} in options while importing")
            end
          end
  
          shards_error_count = _create_index_and_import_data(import_db_query, merged_options)
          if merged_options[:verify_count]
            _verify_index_doc_count(import_db_query, merged_options)
          end
        end
  
        puts error_count
        return error_count
      end
  
      # Wrapper of import method
      # Updates and index refresh_interval setting for faster indexing
      # When options[:force] is true, the index in deleted and recreated with
      # mappings and settings
      # import_db_query is a active_record query
      def _create_index_and_import_data(import_db_query, options)
        error_count = 0
        strategy = options[:strategy]
        index_name = options[:index]
  
        #this is required because import does not support settings
        # if force is true, the index in deleted and re-created
        strategy.create_index({
          force: options[:force],
          index: index_name,
          mappings: options[:mappings],
          settings: options[:settings]
        })
  
        strategy.client.indices.put_settings(
          index: index_name,
          body: { index: { refresh_interval: -1 } }
        )
  
        error_count = import(
          force: false,
          index: index_name,
          batch_size: options[:batch_size],
          refresh: options[:refresh],
          scope: options[:scope],# for some reason it only works if the query is defined inside the 'query' lambda
          strategy: options[:strategy],
          transform: options[:transform],
          query: -> {
            strategy.reindexing_includes_proc.call(import_db_query)
          }
        ) do |response|
            puts "#{(response['items'].size.to_f * 1000 / response['took']).round(0)}/s"
        end
  
        strategy.client.indices.put_settings(
          index: index_name,
          body: { index: { refresh_interval: '1s' } }
        )
  
        error_count
      end
  
      # verifies that an index contains the same amount of
      # documents as the database for a specific db and es query.
      def _verify_index_doc_count(import_db_query, options)
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
  
      def import(options={}, &block)
        errors       = []
        refresh      = options.delete(:refresh)   || false
        target_index = options.delete(:index)
        target_type  = options.delete(:type)
        strategy    = options.delete(:strategy)
        transform    = options.delete(:transform) || __transform
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
  
        __find_in_batches(options) do |batch|
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

        strategies = self.instance_variable_get('@indexing_strategies') || []
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
        strategies = self.instance_variable_get('@indexing_strategies') || []
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
        "#{Rails.env}_#{_to_index_model_name}_"
      end

      # all class indices must comply with this base name
      #
      # @return [void]
      def delete_all_klass_indices!
        ElasticsearchRepositories.client.cat.indices(
          index: "#{self._base_index_name}*", h: ['index', 'docs.count']
        ).each_line do |line|
          index, count = line.chomp.split("\s")
          if index.present?
            puts "deleting #{index}"
            ElasticsearchRepositories.client.indices.delete(index: index)
          end
        end
      end
      
    end

    module InstanceMethods

      # @todo this should be on ClassMethods
      def self.included(base)
        base.public_send :extend, Adapter.new(base).importing_mixin
      end

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