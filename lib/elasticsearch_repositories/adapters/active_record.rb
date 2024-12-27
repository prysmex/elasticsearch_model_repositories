# frozen_string_literal: true

module ElasticsearchRepositories
  module Adapters

    # An adapter for ActiveRecord-based models
    #
    module ActiveRecord

      # register adapter
      Adapter.register self, ->(klass_or_klasses) {
        defined?(::ActiveRecord::Base) &&
          klass_or_klasses.respond_to?(:ancestors) &&
          klass_or_klasses.ancestors.include?(::ActiveRecord::Base)
      }

      # Module for implementing methods and logic related to fetching records from the database
      #
      module Records

        # @return [ActiveRecord::Relation]
        def records
          ar_relation = klass_or_klasses.where(klass_or_klasses.primary_key => ids)
          ar_relation = ar_relation.includes(options[:includes]) if options[:includes]

          # Re-order records based on the order from Elasticsearch hits
          # by redefining `to_a` or `records`, unless the user has called `order()`
          ar_relation.instance_exec(response.results) do |results|
            break unless self # TODO: why?

            # override method in ActiveRecord_Relation instance
            define_singleton_method(:records) do
              self.load

              # sort unless user called `order()`
              if order_values.present?
                @records
              else
                @records.sort_by do |record|
                  results.index do |result|
                    result.id == record.id.to_s
                  end
                end
              end
            end
          end

          ar_relation
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
        #
        #     after_commit lambda {  call_indexing_methods('create', record)  },  on: :create
        #     after_commit lambda {  call_indexing_methods('update', record) },  on: :update
        #     after_commit lambda {  call_indexing_methods('delete', record) },  on: :destroy
        #
        #     def call_indexing_methods(event_name, record)
        #       self.class.indexing_strategies.each do |strategy|
        #         strategy.index_record_to_es(event_name, record)
        #       end
        #     end
        #
        #   end
        # end
      end

      # Module for efficiently fetching records from the database to import them into the index
      #
      module Importing

        BULKIFY_PROC = ->(model, strategy) do
          if strategy.index_without_id
            { index: { data: strategy.as_indexed_json(model) } }
          else
            { index: { _id: strategy.custom_doc_id(model) || model.id, data: strategy.as_indexed_json(model) } }
          end
        end

        # Fetch batches of records from the database (used by the import method)
        #
        # @see http://api.rubyonrails.org/classes/ActiveRecord/Batches.html ActiveRecord::Batches.find_in_batches
        #
        def self.find_in_batches(model, query: nil, scope: nil, **)
          model = model.public_send(scope) if scope
          model = model.instance_exec(&query) if query

          model.find_in_batches(**) do |batch|
            yield(batch) if batch.present?
          end
        end

        # Similar to find_in_batches but with in_batches api
        #
        # @see http://api.rubyonrails.org/classes/ActiveRecord/Batches.html ActiveRecord::Batches.in_batches
        #
        def self.in_batches(model, query: nil, scope: nil, **)
          model = model.public_send(scope) if scope
          model = model.instance_exec(&query) if query

          model.in_batches(**) do |batch|
            yield(batch) if batch.present?
          end
        end

      end

    end

  end
end
