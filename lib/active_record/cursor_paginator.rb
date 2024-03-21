# frozen_string_literal: true

require 'active_record'
require_relative 'cursor_paginator/version'

module ActiveRecord
  class CursorPaginator
    DIRECTIONS = [
      DIRECTION_FORWARD  = :forward,
      DIRECTION_BACKWARD = :backward
    ].freeze

    class ParameterError < StandardError; end
    class InvalidCursorError < ParameterError; end
    class InvalidOrderError < ParameterError; end

    # @param relation [ActiveRecord::Relation]
    #   Relation that will be paginated.
    # @param per_page [Integer, nil]
    #   Number of records to return.
    # @param cursor [String, nil]
    #   Cursor to paginate
    # @param order [Array, Hash, Symbol, nil]
    #   Column to order by. If none is provided, will default to ID column.
    def initialize(relation, per_page: nil, cursor: nil, direction: DIRECTION_FORWARD)
      @is_forward_pagination = direction == DIRECTION_FORWARD
      relation = relation.order(:id) if relation.order_values.empty?
      relation = relation.reverse_order unless @is_forward_pagination
      @fields = extract_order_fields(relation)
      @fields.push({ 'id' => :asc }) if @fields.last.keys.first != 'id'
      @relation = relation.reorder(@fields)
      @cursor = cursor
      @page_size = per_page

      @memos = {}
    end

    # extract order parameter from relation as the format : [ { field1 => :asc}, { field2 => :desc}, ...]
    # @param relation [ActiveRecord::Relation]
    # @return [Array]
    def extract_order_fields(relation)
      orders = relation.order_values
      fields = orders.flat_map do |o|
        case o
        when Arel::Attribute # .order(arel_table[:id])
          { o.name => :asc }
        when Arel::Nodes::Ascending # .order(id: :asc), .order(:id)
          { o.expr.name => :asc }
        when Arel::Nodes::Descending # .order(id: :desc)
          { o.expr.name => :desc }
        when String # .order('id desc')
          o.split(',').map! do |s|
            s.strip!
            matches = s.match(/\A(\w+)(?:\s+(asc|desc))?\Z/i)
            raise InvalidOrderError, 'relation has an unsupported order.' if matches.nil? || matches.length < 3

            { matches[1] => (matches[2] || 'asc').downcase.to_sym }
          end
        else # complex arel expression
          raise InvalidOrderError, 'relation has an unsupported order.'
        end
      end
      fields.flatten
    end

    # Cursor of the first record on the current page
    #
    # @return [String, nil]
    def start_cursor
      return if records.empty?

      cursor_for_record(records.first)
    end

    # Cursor of the last record on the current page
    #
    # @return [String, nil]
    def end_cursor
      return if records.empty?

      cursor_for_record(records.last)
    end

    # Get the total number of records in the given relation
    #
    # @return [Integer]
    def total
      memoize(:total) { @relation.reorder('').size }
    end

    # Check if there is a page before the current one.
    #
    # @return [TrueClass, FalseClass]
    def previous_page?
      if paginate_forward?
        # When paginating forwards and cursor is specified,
        # we have the previous page, because specified cursor may be the end cursor of a page
        @cursor.present?
      else
        # When paginating backwards, if we managed to load one more record than
        # requested, this record will be available on the previous page.
        records_plus_one.size > @page_size
      end
    end

    # Check if there is another page after the current one.
    #
    # @return [TrueClass, FalseClass]
    def next_page?
      if paginate_forward?
        # When paginating forward, if we managed to load one more record than
        # requested, this record will be available on the next page.
        records_plus_one.size > @page_size
      else
        # When paginating backward, in most cases,
        # we have the next page, because specified cursor may be the start cursor of a page
        true
      end
    end

    # Load the correct records and return them in the right order
    #
    # @return [Array<ActiveRecord>]
    def records
      records = records_plus_one.first(@page_size)
      paginate_forward? ? records : records.reverse
    end

    # Check if the pagination direction is forward
    #
    # @return [TrueClass, FalseClass]
    def paginate_forward?
      @is_forward_pagination
    end

    private

    # Apply limit to filtered and sorted relation that contains one item more
    # than the user-requested page size. This is useful for determining if there
    # is an additional page available without having to do a separate DB query.
    # Then, fetch the records from the database to prevent multiple queries to
    # load the records and count them.
    #
    # @return [ActiveRecord::Relation]
    def records_plus_one
      memoize :records_plus_one do
        filtered_and_sorted_relation.first(@page_size + 1)
      end
    end

    # Generate a cursor for the given record and ordering field. The cursor
    # encodes all the data required to then paginate based on it with the given
    # ordering field.
    #
    # If we only order by ID, the cursor doesn't need to include any other data.
    # But if we order by any other field, the cursor needs to include both the
    # value from this other field as well as the records ID to resolve the order
    # of duplicates in the non-ID field.
    #
    # @param record [ActiveRecord] Model instance for which we want the cursor
    # @return [String]
    def cursor_for_record(record)
      unencoded_cursor = @fields.map { |field| { field.keys.first => record[field.keys.first] } }
      Base64.strict_encode64(unencoded_cursor.to_json)
    end

    # Decode the provided cursor. Either just returns the cursor's ID or in case
    # of pagination on any other field, returns a tuple of first the cursor
    # record's other field's value followed by its ID.
    #
    # @return [Integer, Array]
    def decoded_cursor
      memoize(:decoded_cursor) { JSON.parse(Base64.strict_decode64(@cursor)) }
    rescue ArgumentError, JSON::ParserError
      raise InvalidCursorError, 'The given cursor could not be decoded'
    end

    # Ensure that the relation has the ID column and any potential `order_by`
    # column selected. These are required to generate the record's cursor and
    # therefore it's crucial that they are part of the selected fields.
    #
    # @return [ActiveRecord::Relation]
    def relation_with_cursor_fields
      return @relation if @relation.select_values.blank?

      relation = @relation

      @fields.each do |field|
        field = field.keys.first
        relation = relation.select(field) unless @relation.select_values.include?(field)
      end

      relation
    end

    # The given relation with the right ordering applied. Takes custom order
    # columns as well as custom direction and pagination into account.
    #
    # @return [ActiveRecord::Relation]
    def sorted_relation
      relation_with_cursor_fields
    end

    # Applies the filtering based on the provided cursor and order column to the
    # sorted relation.
    #
    # @return [ActiveRecord::Relation]
    def filtered_and_sorted_relation
      memoize :filtered_and_sorted_relation do
        next sorted_relation if @cursor.blank?

        cursor = decoded_cursor
        unless cursor.length == @fields.length && cursor.map { |field| field.keys.first } == @fields.map do |field|
                                                                                               field.keys.first
                                                                                             end
          raise InvalidCursorError, 'The given cursor is mismatched with current query'
        end

        prev_fields = []
        relation = nil
        cursor.zip(@fields).each do |cursor_field, field|
          direction = field.values.first
          # range では 〜より大きいということが表現できないのでarel_tableを使う
          op = direction == :asc ? :gt : :lt
          current_field = [field.keys.first, cursor_field.values.first]
          new_relation = build_filter_query(sorted_relation, op, current_field, prev_fields)
          relation = relation.nil? ? new_relation : relation.or(new_relation)

          prev_fields.push(current_field)
        end
        relation
      end
    end

    # Ensures that given block is only executed exactly once and on subsequent
    # calls returns result from first execution. Useful for memoizing methods.
    #
    # @param key [Symbol]
    #   Name or unique identifier of the method that is being memoized
    # @yieldreturn [Object]
    # @return [Object] Whatever the block returns
    def memoize(key)
      return @memos[key] if @memos.has_key?(key)

      @memos[key] = yield
    end

    # Modelを[{ col1: :asc}, { col2: :asc}, { col3: :asc}] でソートする場合以下のようにする
    # Model.where('col1 > ?').
    #   or(Model.where('col1 = ?').where('col2 > ?')).
    #   or(Model.where('col1 = ?').where('col2 = ?')).where('col3 > ?))
    #
    # @return [ActiveRecord::Relation]
    def build_filter_query(sorted_relation, op, current_field, prev_fields)
      relation = sorted_relation
      prev_fields.each do |col, val|
        relation = relation.where(relation.arel_table[col].send(:eq, val))
      end
      col, val = current_field
      relation.where(relation.arel_table[col].send(op, val))
    end
  end
end
