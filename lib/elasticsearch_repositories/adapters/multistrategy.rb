module ElasticsearchRepositories
  module Adapter
    module Multistrategy

      Adapter.register self, lambda { |klass| klass.is_a? Array }

      module Records

        # Returns a collection of model instances, possibly of different classes (ActiveRecord, Mongoid, ...)
        #
        # @note The order of results in the Elasticsearch response is preserved
        #
        def records
          records_by_type = __records_by_type

          records = response.response["hits"]["hits"].map do |hit|
            records_by_type[ __type_for_hit(hit) ][ hit[:_id] ]
          end

          records.compact
        end

        # Returns the collection of records grouped by class based on `_type`
        #
        # Example:
        #
        # {
        #   Foo  => {"1"=> #<Foo id: 1, title: "ABC"}, ...},
        #   Bar  => {"1"=> #<Bar id: 1, name: "XYZ"}, ...}
        # }
        #
        # @api private
        #
        def __records_by_type
          result = __ids_by_type.map do |klass, ids|
            records = __records_for_klass(klass, ids)
            ids     = records.map(&:id).map(&:to_s)
            [ klass, Hash[ids.zip(records)] ]
          end

          Hash[result]
        end

        # Returns the collection of records for a specific type based on passed `klass`
        #
        # @api private
        #
        def __records_for_klass(klass, ids)
          adapter = __adapter_for_klass(klass)
          case
            when ElasticsearchRepositories::Adapter::ActiveRecord.equal?(adapter)
              multi_includes = self.options .try(:[], :multimodel_includes)
      
              klass_includes = []
              if multi_includes.is_a? Hash
                klass_includes << multi_includes.try(:[], klass.name.underscore.to_sym) 
                klass_includes << multi_includes.try(:[], :all)
                klass_includes = klass_includes.flatten.compact
              else
                klass_includes = multi_includes
              end
              klass.where(klass.primary_key => ids).includes(klass_includes)
            # when ElasticsearchRepositories::Adapter::Mongoid.equal?(adapter)
            #   klass.where(:id.in => ids)
          else
            klass.find(ids)
          end
        end

        # Returns the record IDs grouped by class based on type `_type`
        #
        # Example:
        #
        #   { Foo => ["1"], Bar => ["1", "5"] }
        #
        # @api private
        #
        def __ids_by_type
          ids_by_type = {}

          response.response["hits"]["hits"].each do |hit|
            type = __type_for_hit(hit)
            ids_by_type[type] ||= []
            ids_by_type[type] << hit[:_id]
          end
          ids_by_type
        end

        # Returns the class of the model corresponding to a specific `hit` in Elasticsearch results
        #
        # @api private
        #
        # Caching classes is not a good idea since the app reloads in development enviroment
        def __type_for_hit(hit)
          # @@__types ||= {}
          # key = hit[:_index]

          # @@__types[key] ||= begin
          #   response.strategy.host_class.detect do |model|
          #     model.to_s == hit._source[:type]
          #   end
          # end

          response.strategy.host_class.detect do |model|
            model.to_s == hit._source[:type]
          end
        end

        # def __no_type?(hit)
        #   hit[:_type].nil? || hit[:_type] == '_doc'
        # end

        # Returns the adapter registered for a particular `klass` or `nil` if not available
        #
        # @api private
        #
        def __adapter_for_klass(klass)
          Adapter.adapters.select { |name, checker| checker.call(klass) }.keys.first
        end

      end

    end
  end
end