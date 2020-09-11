module ElasticsearchRepositories
  module Importing

    # by using adapters
    def self.included(base)
      adapter = Adapter.from_class(base)
      # puts base
      # puts adapter.importing_mixin
      base.__send__ :include, adapter.importing_mixin
    end

    def self._call_reindex_iterators(*payload, &block)
      self.instance_variable_get('@indexing_strategies').each do |strategy|
        strategy.public_send(:reindexing_index_iterator, *payload, &block)
      end
    end

    def self.reload_indices!(options={})

      required_options = [
        :batch_size, :index, :es_query, :es_query_options,
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
          :import_db_query,
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
    def self._create_index_and_import_data(import_db_query, options)
      error_count = 0
      strategy = options[:strategy]
      index_name = option[:index_name]

      #this is required because import does not support settings
      # if force is true, the index in deleted and re-created
      strategy.create_index!({
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
          strategy.reindexing_includes_proc(
            import_db_query
          )
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
    def self._verify_index_doc_count(import_db_query, options)
      index_name = option[:index]
      es_query = option[:es_query]

      db_count = import_db_query
          .count
      sleep(2)
      es_count = self
          .search(es_query, option[:es_query_options])
          .response.hits.total.value
      if db_count != es_count
        puts "MISMATCH! -> (DB=#{db_count}, ES=#{es_count}) for query: #{es_query}"
      else
        puts "(DB=#{db_count}, ES=#{es_count}) for query: #{es_query}"
      end
      db_count == es_count
    end

    def self.import(options={}, &block)
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
        strategy.create_index! force: true, index: target_index
      elsif !strategy.index_exists? index: target_index
        raise ArgumentError,
              "#{target_index} does not exist to be imported into. Use create_index! or the :force option to create it."
      end

      __find_in_batches(options) do |batch|
        params = {
          index: target_index,
          type:  target_type,
          body:  __batch_to_bulk(batch, strategy, transform)
        }

        params[:pipeline] = pipeline if pipeline

        response = client.bulk params

        yield response if block_given?

        errors +=  response['items'].select { |k, v| k.values.first['error'] }

        if options[:batch_sleep] && options[:batch_sleep] > 0
          sleep options[:batch_sleep]
        end
      end

      strategy.refresh_index! index: target_index if refresh

      case return_value
        when 'errors'
          errors
        else
          errors.size
      end
    end

    def self.__batch_to_bulk(batch, strategy, transform)
      batch.map { |model| transform.call(model, strategy) }
    end

  end
end