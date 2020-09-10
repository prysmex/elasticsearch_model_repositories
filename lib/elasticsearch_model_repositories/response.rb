module ElasticsearchModelRepositories
  module Response
    class Response < Elasticsearch::Model::Response::Response
  
      # Returns the collection of "hits" from Elasticsearch
      #
      # @return [Results]
      #
      def results
        @results ||= Elasticsearch::Model::Response::Results.new(klass.instance_variable_get('@host'), self)
      end
  
      # Returns the collection of records from the database
      #
      # @return [Records]
      #
      def records(options = {})
        @records ||= Elasticsearch::Model::Response::Records.new(klass.instance_variable_get('@host'), self, options)
      end
  
    end
  end
end