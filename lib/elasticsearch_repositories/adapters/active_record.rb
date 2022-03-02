module ElasticsearchRepositories
  module Adapters

    # An adapter for ActiveRecord-based models
    #
    module ActiveRecord

      # register adapter
      Adapter.register self, lambda {|klass|
        !!defined?(::ActiveRecord::Base) &&
            klass.respond_to?(:ancestors) &&
            klass.ancestors.include?(::ActiveRecord::Base)
      }

      # Module for implementing methods and logic related to fetching records from the database
      #
      module Records

        # @return [ActiveRecord::Relation]
        def records
          sql_records = klass.where(klass.primary_key => ids)
          sql_records = sql_records.includes(self.options[:includes]) if self.options[:includes]

          # Re-order records based on the order from Elasticsearch hits
          # by redefining `to_a` or `records`, unless the user has called `order()`
          #
          sql_records.instance_exec(response.results) do |hits|
            if self

              ar_records_method_name = if defined?(::ActiveRecord) && ::ActiveRecord::VERSION::MAJOR >= 5
                :records
              else
                :to_a
              end
  
              define_singleton_method(ar_records_method_name) do
  
                if defined?(::ActiveRecord) && ::ActiveRecord::VERSION::MAJOR >= 4
                  self.load
                else
                  self.__send__(:exec_queries)
                end
  
                # sort unless user called `order()`
                if !self.order_values.present?
                  @records.sort_by do |record|
                    hits.index do |hit|
                      hit.id == record.id.to_s
                    end
                  end
                else
                  @records
                end
  
              end

            end
          end

          sql_records
        end

      end

      # Module for implementing methods and logic related to hooking into model lifecycle
      # (e.g. to perform automatic index updates)
      #
      # @see http://api.rubyonrails.org/classes/ActiveModel/Callbacks.html
      module Callbacks

        # # Handle index updates (creating, updating or deleting documents)
        # # when the model changes, by hooking into the lifecycle
        # #
        # # @see http://guides.rubyonrails.org/active_record_callbacks.html
        # #
        # def self.included(base)
        #   base.class_eval do
        #     after_commit lambda {  _call_indexing_methods('create', record)  },  on: :create
        #     after_commit lambda {  _call_indexing_methods('update', record) },  on: :update
        #     after_commit lambda {  _call_indexing_methods('delete', record) },  on: :destroy
      
        #     def _call_indexing_methods(event_name, record)
        #       self.class.indexing_strategies.each do |strategy|
        #         strategy.public_send(:index_record_to_es, event_name, record)
        #       end
        #     end
        #   end
        # end
      end

      # Module for efficiently fetching records from the database to import them into the index
      #
      module Importing

        BULKIFY_PROC = lambda do |model, strat|
          if strat.index_without_id
            { index: { data: strat.as_indexed_json(model) } }
          else
            { index: { _id: model.id, data: strat.as_indexed_json(model) } }
          end
        end

        # Fetch batches of records from the database (used by the import method)
        #
        # @see http://api.rubyonrails.org/classes/ActiveRecord/Batches.html ActiveRecord::Batches.find_in_batches
        #
        def self.find_in_batches(model, query: nil, scope: nil, find_params: {}, &block)
          model = model.__send__(scope) if scope
          model = model.instance_exec(&query) if query

          model.find_in_batches(**find_params) do |batch|
            yield(batch) if batch.present?
          end
        end

      end

    end

  end
end
