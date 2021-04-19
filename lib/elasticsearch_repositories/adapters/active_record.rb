module ElasticsearchRepositories
  module Adapter

    # An adapter for ActiveRecord-based models
    #
    module ActiveRecord

      Adapter.register self, lambda {|klass|
        !!defined?(::ActiveRecord::Base) &&
            klass.respond_to?(:ancestors) &&
            klass.ancestors.include?(::ActiveRecord::Base)
      }

      module Records
        attr_writer :options

        def options
          @options ||= {}
        end

        # Returns an `ActiveRecord::Relation` instance
        #
        def records
          sql_records = klass.where(klass.primary_key => ids)
          sql_records = sql_records.includes(self.options[:includes]) if self.options[:includes]

          # Re-order records based on the order from Elasticsearch hits
          # by redefining `to_a`, unless the user has called `order()`
          #
          sql_records.instance_exec(response.results) do |hits|
            ar_records_method_name = :to_a
            ar_records_method_name = :records if defined?(::ActiveRecord) && ::ActiveRecord::VERSION::MAJOR >= 5

            define_singleton_method(ar_records_method_name) do
              if defined?(::ActiveRecord) && ::ActiveRecord::VERSION::MAJOR >= 4
                self.load
              else
                self.__send__(:exec_queries)
              end
              if !self.order_values.present?
                @records.sort_by do |record|
                  hits.index do |hit|
                    hit.id == record.id.to_s
                  end
                end
              else
                @records
              end
            end if self
          end

          sql_records
        end

        # Prevent clash with `ActiveSupport::Dependencies::Loadable`
        #
        def load
          records.__send__(:load)
        end
      end

      # module Callbacks

      #   # Handle index updates (creating, updating or deleting documents)
      #   # when the model changes, by hooking into the lifecycle
      #   #
      #   # @see http://guides.rubyonrails.org/active_record_callbacks.html
      #   #
      #   def self.included(base)
      #     base.class_eval do
      #       after_commit lambda {  _call_indexing_methods('create', record)  },  on: :create
      #       after_commit lambda {  _call_indexing_methods('update', record) },  on: :update
      #       after_commit lambda {  _call_indexing_methods('delete', record) },  on: :destroy
      
      #       def _call_indexing_methods(event_name, record)
      #         self.class.instance_variable_get('@indexing_strategies').each do |strategy|
      #           strategy.public_send(:index_record_to_es, event_name, record)
      #         end
      #       end
      #     end
      #   end
      # end

      module Importing

        # Fetch batches of records from the database (used by the import method)
        #
        #
        # @see http://api.rubyonrails.org/classes/ActiveRecord/Batches.html ActiveRecord::Batches.find_in_batches
        #
        def __find_in_batches(options={}, &block)
          query = options.delete(:query)
          named_scope = options.delete(:scope)
          preprocess = options.delete(:preprocess)

          scope = self
          scope = scope.__send__(named_scope) if named_scope
          scope = scope.instance_exec(&query) if query

          scope.find_in_batches(**options) do |batch|
            batch = self.__send__(preprocess, batch) if preprocess
            yield(batch) if batch.present?
          end
        end

        #TODO support strategies
        def __transform
          lambda do |model, strat|
            if strat.index_without_id
              { index: { data: strat.as_indexed_json(model) } }
            else
              { index: { _id: model.id, data: strat.as_indexed_json(model) } }
            end
          end
        end

      end

    end
  end
end
