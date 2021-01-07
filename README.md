# ElasticsearchModelRepositories

This gem was created to remove the dependency of indices being tied 1-1 to an ActiveModel class by implementing an 'indexing strategies' pattern, allowing for much more flexibility on the design of your Elasticsearch indices.

- A model can contain one or more 'strategies' (maybe you want to analize/search data in different ways?)
- A strategy can involve one or more Elasticsearch indices (maybe you want to index data by year?)
- A single index can even contain data from multiple models!

The best thing is that we manage to do this with small impact on your models and a clean mental model by keeping all the business logic inside your strategy classes.

The creation of this gem was inspired on Elasticsearch's own [elasticsearch-model](https://github.com/elastic/elasticsearch-rails/tree/master/elasticsearch-model) gem.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'elasticsearch_model_repositories'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install elasticsearch_model_repositories

## Usage

Lets create our first indexing strategy by extending `ElasticsearchRepositories::BaseStrategy`

```ruby
class Person

  extend ElasticsearchRepositories::Model::ClassMethods
  include ElasticsearchRepositories::Model::InstanceMethods
  include ElasticsearchRepositories::Importing

  register_strategy Searchable::Strategies::Simple do
    set_mappings(dynamic: 'true') do
      # your mappings
    end
    
    def as_indexed_json(record)
      super # you can customize this for each class
    end
  end

  after_commit -> (record) {
    _call_indexing_methods('create', record)
  }, on: :create

  after_commit -> (record) {
    _call_indexing_methods('update', record)
  }, on: :update

  after_commit -> (record) {
    _call_indexing_methods('delete', record)
  }, on: :destroy

  def _call_indexing_methods(event_name, record)
    self.class.indexing_strategies.each do |strategy|
      strategy.public_send(:index_record_to_es, event_name, record)
    end
  end

  def self._base_index_name
    "#{Rails.env}_#{self.name.underscore.dasherize.pluralize}_"
  end

end

class Simple < ElasticsearchRepositories::BaseStrategy

  #############
  #index naming
  #############
    
  # The index_name for a specific record (used when create/update/destroy)
  def target_index_name(record)
    search_index_name
  end

  # The name of the index (if mu)
  def search_index_name
    host_class._base_index_name # in this case, host_class is Person
  end

  def current_index_name
    search_index_name
  end

  ##############
  #serialization
  ##############

  # default serialization
  def as_indexed_json(record)
    record.as_json
  end

end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/elasticsearch_model_repositories.