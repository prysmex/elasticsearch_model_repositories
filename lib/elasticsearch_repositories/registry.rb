# frozen_string_literal: true

module ElasticsearchRepositories
  # used to keep track which classes have the ElasticsearchRepositories::Model
  # module included
  class ClassRegistry

    def initialize
      @models = []
    end

    # Returns the unique instance of the registry (Singleton)
    #
    # @api private
    #
    def self.__instance
      @__instance ||= new
    end

    # Adds a model to the registry
    #
    def self.add(klass)
      __instance.add(klass)
    end

    # Returns an Array of registered models
    #
    def self.all
      __instance.models
    end

    # Adds a model to the registry
    #
    def add(klass)
      @models << klass
    end

    # Returns a copy of the registered models
    #
    def models
      @models
    end

  end
end