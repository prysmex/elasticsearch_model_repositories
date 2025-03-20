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

        # @param [ActiveRecord::Relation]
        # @return [ActiveRecord::Relation]
        def self.override_methods!(ar_relation, response, records)
          allow_ar_order = records.options.fetch(:allow_ar_order, ElasticsearchRepositories.allow_ar_order)
          # Re-order records based on the order from Elasticsearch hits
          # by redefining `to_a` or `records`, unless the user has called `order()`
          ar_relation.instance_exec(response.results) do |results|
            break unless self # TODO: why?

            # @override https://github.com/rails/rails/blob/v7.2.2/activerecord/lib/active_record/relation.rb#L335
            #
            # override method in ActiveRecord_Relation instance to
            # sort unless user called `order()`
            define_singleton_method(:records) do
              if order_values.present? && !allow_ar_order
                raise StandardError.new(
                  'ordering values via AR require passing allow_ar_order since it can cause ' \
                  'unexpected results, e.g. calling .records.first, which would reorder ' \
                  'instead of returning the first element'
                )
              end

              load
              return @records if order_values.present?

              result_index_map = results.each_with_index.to_h { |r, index| [r.id, index] }
              @records.sort_by { |r| result_index_map[r.id.to_s] || Float::INFINITY }
            end

            # @override https://github.com/rails/rails/blob/v7.2.2/activerecord/lib/active_record/relation/calculations.rb#L287
            # Needed since pluck does not call overriden 'records' method
            define_singleton_method(:pluck) do |*args|
              unless allow_ar_order
                raise StandardError.new(
                  'pluck requires passing allow_ar_order since it ignores the order of the results'
                )
              end

              super(*args)
            end

            # @override https://github.com/rails/rails/blob/v7.2.2/activerecord/lib/active_record/relation/spawn_methods.rb#L9
            # Ensures ActiveRecord::Relation instances created by chaining (pluck, join, includes, where, etc..) are
            # also overriden
            define_singleton_method(:spawn) do
              ElasticsearchRepositories::Adapters::ActiveRecord::Records.override_methods!(
                super(),
                response,
                records
              )
            end
          end

          ar_relation
        end

        # @return [ActiveRecord::Relation]
        def records
          record_ids = ids
          return klass_or_klasses.unscoped.none if record_ids.empty?

          ar_relation = klass_or_klasses.where(klass_or_klasses.primary_key => record_ids)
          ar_relation = ar_relation.includes(options[:includes]) if options[:includes]

          ElasticsearchRepositories::Adapters::ActiveRecord::Records.override_methods!(ar_relation, response, self)
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
          index = { data: strategy.reindex_as_indexed_json(model) }
          index[:_id] = strategy.custom_doc_id(model) || model.id unless strategy.index_without_id

          { index: }
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
