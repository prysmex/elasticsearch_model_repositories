module ElasticsearchModelRepositories
  module Model

    module ClassMethods
      
      attr_accessor :indexing_strategies

      # Register a new indexing strategy to the model
      # Name paramter is used if updating the strategy later on is desired
      def register_strategy(strategy_klass, name=nil, &block)
        strategies = self.instance_variable_get('@indexing_strategies') || []
        strategy = strategies.find{|s| s.instance_variable_get('@name') == name }
        if strategy
          raise StandardError.new("deplicate strategy name '#{name}' on model #{self.name}")
        else
          strategy = strategy_klass.new(self, ::Elasticsearch::Model.client, name, &block)
          strategies.push(strategy)
          self.instance_variable_set('@indexing_strategies', strategies)
        end
      end

      # Update an indexing strategy by name
      def update_strategy(name=nil, &block)
        strategies = self.instance_variable_get('@indexing_strategies') || []
        strategy = strategies.find{|s| s.instance_variable_get('@name') == name }
        if strategy
          strategy.update(&block)
        else
          raise StandardError.new("strategy '#{name}' not found on model #{self.name}")
        end
      end

      #the first strategy is considered the main one for now
      def default_indexing_strategy
        self.indexing_strategies.first
      end

      # defines how a model's name is embedded in an index name
      # UnsafeActReport => unsafe-act-report
      def _to_index_model_name
        self.name.underscore.dasherize.pluralize
      end

      #this base name is a contract to be followed by each class
      def _base_index_name
        "#{Rails.env}_#{_to_index_model_name}_"
      end

      #all class indices must comply with this base name
      def self.delete_all_klass_indices!
        Elasticsearch::Model.client.cat.indices(
          index: "#{self._base_index_name}*", h: ['index', 'docs.count']
        ).each_line do |line|
          index, count = line.chomp.split("\s")
          if index.present?
            puts "deleting #{index}"
            Elasticsearch::Model.client.indices.delete(index: index)
          end
        end
      end
      
    end

    module InstanceMethods

      def index_to_all_indices
        self.class.indexing_strategies.each do |strategy|
          strategy.index_record_to_es('create', self)
        end
      end
  
      def _index_document(action, strategy)
      end

    end

    # module Callbacks

    #   after_commit lambda {  _call_indexing_methods('create', record)  },  on: :create
    #   after_commit lambda {  _call_indexing_methods('update', record) },  on: :update
    #   after_commit lambda {  _call_indexing_methods('delete', record) },  on: :destroy

    #   def _call_indexing_methods(event_name, record)
    #     self.class.instance_variable_get('@indexing_strategies').each do |strategy|
    #       strategy.public_send(:index_record_to_es, event_name, record)
    #     end
    #   end
      
    # end

  end
end