# frozen_string_literal: true

module ElasticsearchRepositories
  module Multistrategy

    # Wraps a collection of strategies to support multistrategy-querying
    # @see ElasticsearchRepositories.search
    class MultistrategyWrapper
      attr_reader :strategies

      # @param strategies [Strategy] The list of strategies across which the search will be performed
      def initialize(strategies)
        @strategies = strategies
      end

      def search_index_name
        strategies.map(&:search_index_name)
      end

      # Get the common client for all strategies
      # @return Elastic::Transport::Client
      def client
        clients = strategies.map(&:client).uniq

        raise StandardError.new('Strategies must implement same client') unless clients.size == 1

        clients.first
      end

      def host_class
        strategies.map(&:host_class)
      end

    end

  end
end