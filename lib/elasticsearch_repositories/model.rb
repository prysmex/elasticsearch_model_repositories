module ElasticsearchRepositories
  module Model
    
    module ClassMethods
            
      attr_accessor :indexing_strategies

      # Register a new indexing strategy to the model
      # Name paramter is used if updating the strategy later on is desired
      def register_strategy(strategy_klass, name='main', &block)
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
      def update_strategy(name, &block)
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

      def index_to_all_indices
        self.class.indexing_strategies.each do |strategy|
          strategy.index_record_to_es('create', self)
        end
      end
  
      def _index_document(action, options)
        raise NotImplementedError('need to implement own _index_document method')
      end

    end

  end
end