module ElasticsearchRepositories
  module Response

    class Suggestion < ::Hash
      # def terms
      #   self.to_a.map { |k,v| v.first['options'] }.flatten.map {|v| v['text']}.uniq
      # end
    end

  end
end
