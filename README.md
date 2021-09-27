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

```ruby
bundle
```

Or install it yourself as:

```ruby
gem install elasticsearch_model_repositories
```

## Usage

Lets create our first indexing strategy by extending `ElasticsearchRepositories::BaseStrategy`

```ruby
class Simple < ElasticsearchRepositories::BaseStrategy

  # The index_name for a specific record (used for update/destroy)
  def target_index_name(record)
    search_index_name
  end

  # The name of the index when searching data
  def search_index_name
    host_class._base_index_name # in this case, host_class is Person
  end

  # The name of the index to use when creating a new record (create)
  def current_index_name
    search_index_name
  end

end
```

Here is a list of methods that you may want to consider overriding on your custom strategy:

- target_index_name
- search_index_name
- current_index_name
- reindexing_index_iterator
- index_without_id
- as_indexed_json

Now lets register this strategy into a model.
It is important to add the following lines to your model that provide the methods for registering strategies, indexing, reindexing, and some other utilities.

```ruby
  include ElasticsearchRepositories::Model
```

```ruby
class Person

  include ElasticsearchRepositories::Model

  after_commit -> (record) {
    _call_indexing_methods('create', record)
  }, on: :create

  after_commit -> (record) {
    _call_indexing_methods('update', record)
  }, on: :update

  after_commit -> (record) {
    _call_indexing_methods('delete', record)
  }, on: :destroy

  # You can register as many strategies as you want to a model.
  # By adding code into the block, you can override methods for this specific
  # strategy instance
  register_strategy Simple do

    set_mappings(dynamic: 'true') do
      # your mappings for this class
    end

    def as_indexed_json(record)
      # customize serialization for this class 
      super.merge(record.as_json)
    end

  end

  def _call_indexing_methods(event_name, record)
    self.class.indexing_strategies.each do |strategy|
      strategy.public_send(:index_record_to_es, event_name, record)
    end
  end

  # Define this method in case you want to customize index naming
  def self._base_index_name
    "#{Rails.env}_#{self.name.underscore.dasherize.pluralize}_"
  end

  # This method is called by the gem and needs to be implemented
  # Here is where you actually index to ES, you may call a Sidekiq worker
  # that asyncronously indexes the record.
  def _index_document(action, options={})
    SomeIndexerWorker.perform_later(
      action,
      options
    )
  end

end
```

And there we have it, we have registered our `Simple` strategy into our model and used ActiveRecord's hooks to call the indexing methods.

To keep our code DRY lets create a concern that can be added to our models that we want to index to elasticsearch.

```ruby
module Searchable

  class_methods do
    include ElasticsearchRepositories::Model::ClassMethods

    def self._base_index_name
      "#{Rails.env}_#{self.name.underscore.dasherize.pluralize}_"
    end
  end

  included do
    include ElasticsearchRepositories::Model::InstanceMethods

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

    def _index_document(action, options={})
      SomeIndexerWorker.perform_later(
        action,
        options
      )
    end
  end

end
```

We then can add this concern to our model

```ruby
class Person
  include Searchable

  register_strategy Simple do

    set_mappings(dynamic: 'true') do
      # your mappings for this class
    end

    def as_indexed_json(record)
      # customize serialization for this class
      super.merge(record.as_json)
    end

  end

end
```

Now that we have our model correctly setup, lets explore some of the methods we have available.

```ruby
# get the instance of the strategy for the class
simple_indexing_strategy = Person.indexing_strategies.first
#or
simple_indexing_strategy = Person.default_indexing_strategy

##########
#indexing#
##########
Person.create({name: 'Yoda'}) # this will create the record on ES with all registered strategies
Person.update({name: 'John'}) # this will update the record on ES with all registered strategies
Person.destroy # this will delete the record from ES with all registered strategies
Person.first.index_to_all_indices # will index (create/update) the document with all registered strategies
simple_indexing_strategy.index_record_to_es('update', Person.first) # to only this specific strategy

# to serialize the record with a specific strategy
simple_indexing_strategy.as_indexed_json(Person.first) # returns the serialized json

simple_indexing_strategy.search({query: {match_all: {}}})

#reload all registered indices
Person.reload_indices!({})
```

Now lets create an indexing strategy that uses yearly indices

```ruby
class Yearly < ElasticsearchRepositories::BaseStrategy

  #############
  #index naming
  #############

  # Returns an index name for dated indices
  def _build_dated_index_name(date)
    host_class._base_index_name + "#{date.year}"
  end

  # When a search is executed, replace everything after the first digit on the index_name 
  # with * so all the data is reachable.
  def search_index_name
    _build_dated_index_name(Time.now).sub(/\d.*/, '*')
  end

  # Returns the index name of a particular db record
  def target_index_name(record)
    _build_dated_index_name(record.created_at)
  end

  def current_index_name
    _build_dated_index_name(Time.now)
  end

  ##########
  #importing
  ##########

  # Since we have special business logic of how to index the data (divided into yearly indices) we need to override how the data gets reindexed.
  def reindexing_index_iterator(start_time = nil, end_time = nil)

    start_time = (start_time || host_class.minimum('created_at'))&.beginning_of_year
    end_time = (end_time || host_class.maximum('created_at'))&.end_of_year
    if start_time && end_time
      number_of_years = (end_time.year)-(start_time.year) + 1
      (0...number_of_years).each do |month|
        _start = start_time + month.years
        _end = _start + 1.years

        # this is the important part, you need to yield a splatted array
        # with the following parameters:
        # 1) AR relation object with query to fetch records to import
        # 2) reindexing options hash
        yield(
          host_class.where('created_at >= ? and created_at < ?', _start, _end),
          {
            strategy: self,
            index: _build_dated_index_name(_start),
            index_without_id: index_without_id,
            settings: settings.to_hash,
            mappings: mappings.to_hash,
            es_query: { query: { bool:{ filter: [ range: { created_at: { gte: _start, lt: _end  } } ] } } }
          }
        )
      end
    end
  end

end
```

Now lets add this Yearly strategy into our model

```ruby
class Person
  include Searchable

  register_strategy Simple do

    set_mappings(dynamic: 'true') do
      # your mappings for this class
    end

    def as_indexed_json(record)
      # customize serialization for this class 
      super.merge(record.as_json)
    end

  end

  register_strategy Yearly do

    set_mappings(dynamic: 'true') do
      # your mappings for this class
    end

    def as_indexed_json(record)
      # customize serialization for this class 
      super.merge(record.as_json)
    end

  end

end
```

### Multimodel searching

```ruby
location_response = ElasticsearchRepositories.search(
  {query: {match_all: {}}}, #elasticsearch query
  [Person].map(&:default_indexing_strategy) #array of strategies to search
)
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/elasticsearch_model_repositories.