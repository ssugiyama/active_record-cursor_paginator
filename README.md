# Activerecord::CursorPaginator

This library is an implementation of cursor pagination for ActiveRecord relations based on "https://github.com/xing/rails_cursor_pagination.

Additional features are:
- receives a relation with orders, and it is unnecessary to specify orders toA this library separately
- supports bidirectional pagination.

## Supported environment

- ActiveRecord
- mysql or Postgresql

## Installation

Add the following line to your `Gemfile` and execute `bundle install`

```
gem 'active_record-cursor_paginator'
```

## Usage

```ruby
relation = Post.order(...)
page = ActiveRecord::CursorPaginator.new(relarion, direction: :forward, cursor: '...', per_page: 10)
```

### parameters of CursorPaginator
- cursor: String - cursor to paginate
- per_page: Integer - record count per page (default to 10)
- direction: Symbol - direction to paginate. `:forward` (default) or `:backward`

### response of CursorPaginator

- `page.records`: Array - records splitted per page (Notice: not ActiveRecord::Relation but Array)
- `page.start_cursor`: String - cursor of the first record. used for the backward paginate call.
- `page.end_cursor`: String - cursor of the last record. used for the forward paginate call.
- `page.total`: Integer - total count of relation
- `page.next_page?`:  Boolean - whether having the next page forward or not
- `page.previous_page?`:  Boolean - whether having the next page backward or not

## Caveat

This library does not support the following order expressions

```ruby
Post.order(Arel::Nodes::NamedFunction.new('abs', [Post.arel_table[:display_index]])) # order by arel function
Post.order('abs(display_index)') # order by funtion
Post.order('abs(display_index) asc') # order by function and direction
```

## Development

### Run test

```shell
ADAPTER=mysql bundle exec rspec
ADAPTER=postgresql bundle exec rspec
```

## ToDo

This library automatically appends `id` column to sorting and filtering columns, if it is not the last one.
This feature may cause unnecessary performance deterioration.
So, we plan this feature can be off.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ssugiyama/active_record-cursor_paginator. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/ssugiyama/active_record-cursor_paginator/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Activerecord::CursorPagination project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/ssugiyama/active_record-cursor_paginator/blob/main/CODE_OF_CONDUCT.md).
