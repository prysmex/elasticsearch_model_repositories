module ElasticsearchRepositories
  module Adapters

    #
    # Adapter for multimodel ActiveRecord-based models
    # This is a read only strategy, so no Importing or Callbacks modules
    #
    module Multistrategy

      # register adapter
      Adapter.register self, lambda { |klass_or_klasses| klass_or_klasses.is_a? Array }

      module Records

        # Returns a collection of model instances, possibly of different classes and adapters (ActiveRecord, Mongoid, ...)
        #
        # @note The order of results in the Elasticsearch response must be preserved
        #
        def records
          type_model_cache = {}

          # group ids by model
          # {
          #   Foo => ["1"],
          #   Bar => ["1", "5"]
          # }
          ids_by_type = response.results.each_with_object({}) do |result, obj|
            type = __type_for_result(result)
            model = type_model_cache[type] ||= response.strategy_or_wrapper.host_class.detect do |model|
              __model_to_type(model) == type
            end
            next if model.nil?
            result[:___model_cache___] = model

            obj[model] ||= []
            obj[model] << result.id
          end

          # search by model
          # {
          #   Foo  => {"1"=> #<Foo id: 1, title: "ABC"}, ...},
          #   Bar  => {"1"=> #<Bar id: 1, name: "XYZ"}, ...}
          # }
          records_by_type = ids_by_type.each_with_object({}) do |(model, ids), obj|
            h = obj[model] = {}
            __records_for_model(model, ids).each do |record|
              h[record.id.to_s] = record
            end
          end

          # build array, with original sorting
          response.results.each_with_object([]) do |result, obj|
            # record = records_by_type.dig(type_model_cache[__type_for_result(result)], result.id)
            record = records_by_type.dig(result[:___model_cache___], result.id.to_s)
            obj.push(record) if record
          end
        end

        private

        # Extracts the type from the result used to compare with #__model_to_type
        #
        # @param [ElasticsearchRepositories::Response::Result] result
        # @return [String]
        def __type_for_result(result)
          result.dig('_source', 'type')
        end

        # Converts a class name to a string used to compare with #__type_for_result
        #
        # @param [Class] model
        # @return [String]
        def __model_to_type(model)
          model.name
        end

        # Returns the collection of records for a specific type based on passed `model`
        #
        # @api private
        #
        def __records_for_model(model, ids)
          adapter = __adapter_for_model(model)
          case
          when ElasticsearchRepositories::Adapters::ActiveRecord.equal?(adapter)

            multi_includes = self.options[:multimodel_includes]
            model_includes = []
            if multi_includes.is_a? Hash
              model_includes.concat(multi_includes[model.name.underscore.to_sym])
              model_includes.concat(multi_includes[:all])
              model_includes = model_includes.compact
            else
              model_includes = multi_includes
            end

            model.where(model.primary_key => ids).includes(model_includes)
          else
            raise StandardError.new("#{adapter.name} not implemented in multistrategy adapter")
          end
        end

        # Returns the adapter registered for a particular klass
        #
        # @api private
        #
        def __adapter_for_model(model)
          Adapter.adapters.select { |name, checker| checker.call(model) }.keys.first
        end

      end

    end
    
  end
end