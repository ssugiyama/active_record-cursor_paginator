# frozen_string_literal: true

# require 'active_record'
require 'active_record/cursor_paginator'
require 'spec_helper'
require 'temping'

RSpec.describe ActiveRecord::CursorPaginator do
  it 'has a version number' do
    expect(ActiveRecord::CursorPaginator::VERSION).not_to be nil
  end

  before do
    ActiveSupport::JSON::Encoding.time_precision = 6
    Temping.teardown
    Temping.create(:author) do
      with_columns do |t|
        t.string :name
      end
    end
    Temping.create(:post) do
      belongs_to :author
      with_columns do |t|
        t.integer :author_id
        t.integer :display_index
        t.integer :weight
        t.datetime :posted_at
      end
    end
  end

  context 'paginator' do
    let!(:author_count) { 2 }
    let!(:post_count) { 6 }
    let(:now) { Time.now.floor }
    let(:epsilon) { BigDecimal('0.000001') }
    before do
      authors = []
      (0...author_count).each do |i|
        authors << Author.create(name: "author_#{i}")
      end
      (0...post_count).each do |i|
        Post.create(display_index: i, weight: i % 2, posted_at: now - (i * epsilon), author_id: authors[i % 2].id)
      end
    end

    context 'bidirectional' do
      let(:relation) { Post.order(display_index: :desc) }

      it 'returns proper pages' do
        next_cursor = nil
        prev_cursor = nil
        (0...post_count / 2).each do |i|
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2, cursor: next_cursor)
          expect(page.total).to eq post_count
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.pluck(:display_index)).to eq [post_count - (i * 2) - 1, post_count - (i * 2) - 2]
          next_cursor = page.end_cursor
          prev_cursor = page.start_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'display_index' => records.last.display_index }, { 'id' => records.last.id }]
          expect(JSON.parse(Base64.strict_decode64(prev_cursor))).to eq [{ 'display_index' => records.first.display_index }, { 'id' => records.first.id }]
          expect(page.paginate_forward?).to eq true
          expect(page.next_page?).to eq(i != (post_count / 2) - 1)
          expect(page.previous_page?).to eq(i != 0)
        end
        next_cursor = prev_cursor
        (0...(post_count / 2) - 1).reverse_each do |i|
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2, cursor: next_cursor, direction: :backward)
          expect(page.total).to eq post_count
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(page.paginate_forward?).to eq false
          expect(records.pluck(:display_index)).to eq [post_count - (i * 2) - 1, post_count - (i * 2) - 2]
          prev_cursor = page.end_cursor
          next_cursor = page.start_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'display_index' => records.first.display_index }, { 'id' => records.first.id }]
          expect(JSON.parse(Base64.strict_decode64(prev_cursor))).to eq [{ 'display_index' => records.last.display_index }, { 'id' => records.last.id }]
          expect(page.paginate_forward?).to eq false
          expect(page.next_page?).to eq(i != (post_count / 2) - 1)
          expect(page.previous_page?).to eq(i != 0)
        end
      end

      context 'invalid cursor' do
        let(:relation) { Post.order(display_index: :desc) }

        it 'raises error' do
          expect { ActiveRecord::CursorPaginator.new(relation, per_page: 2, cursor: 'invalid').records }.
            to raise_error(ActiveRecord::CursorPaginator::InvalidCursorError)
        end
      end

      context 'cursor with mismatched length' do
        let(:relation) { Post.order(display_index: :desc) }
        let(:cursor) { Base64.strict_encode64([{ display_index: 1 }].to_json) }

        it 'raises error' do
          expect { ActiveRecord::CursorPaginator.new(relation, per_page: 2, cursor: cursor).records }.
            to raise_error(ActiveRecord::CursorPaginator::InvalidCursorError)
        end
      end

      context 'cursor with mismatched fields' do
        let(:relation) { Post.order(display_index: :desc) }
        let(:cursor) { Base64.strict_encode64([{ foo: 'bar' }, { id: 1 }].to_json) }

        it 'raises error' do
          expect { ActiveRecord::CursorPaginator.new(relation, per_page: 2, cursor: cursor).records }.
            to raise_error(ActiveRecord::CursorPaginator::InvalidCursorError)
        end
      end

      context 'invalid order' do
        let(:relation) { Post.order(Arel.sql('case display_index when 1 then 2 else 1 end')) }

        it 'raises error' do
          expect { ActiveRecord::CursorPaginator.new(relation, per_page: 2).records }.
            to raise_error(ActiveRecord::CursorPaginator::InvalidOrderError)
        end
      end

      context 'order with symbol' do
        let(:relation) { Post.order(:display_index) }

        it 'returns proper page' do
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2)
          expect(page.total).to eq post_count
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.pluck(:display_index)).to eq [0, 1]
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'display_index' => records.last.display_index }, { 'id' => records.last.id }]
        end
      end

      context 'order with arel' do
        let(:relation) { Post.order(Post.arel_table[:display_index]) }

        it 'returns proper page' do
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2)
          expect(page.total).to eq post_count
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.pluck(:display_index)).to eq [0, 1]
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'display_index' => records.last.display_index }, { 'id' => records.last.id }]
        end
      end

      context 'order with field string' do
        let(:relation) { Post.order('display_index') }

        it 'returns proper page' do
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2)
          expect(page.total).to eq post_count
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.pluck(:display_index)).to eq [0, 1]
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'display_index' => records.last.display_index }, { 'id' => records.last.id }]
        end
      end

      context 'order with order string' do
        let(:relation) { Post.order('display_index asc') }

        it 'returns proper page' do
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2)
          expect(page.total).to eq post_count
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.pluck(:display_index)).to eq [0, 1]
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'display_index' => records.last.display_index }, { 'id' => records.last.id }]
        end
      end

      context 'order with arel function' do
        let(:relation) { Post.order(Arel::Nodes::NamedFunction.new('abs', [Post.arel_table[:display_index]])) }

        it 'raises error' do
          expect { ActiveRecord::CursorPaginator.new(relation, per_page: 2).records }.
            to raise_error(ActiveRecord::CursorPaginator::InvalidOrderError)
        end
      end

      context 'order with string with function' do
        let(:relation) { Post.order('abs(display_index)') }

        it 'raises error' do
          expect { ActiveRecord::CursorPaginator.new(relation, per_page: 2).records }.
            to raise_error(ActiveRecord::CursorPaginator::InvalidOrderError)
        end
      end

      context 'order with string with function and order' do
        let(:relation) { Post.order('abs(display_index) asc') }

        it 'raises error' do
          expect { ActiveRecord::CursorPaginator.new(relation, per_page: 2).records }.
            to raise_error(ActiveRecord::CursorPaginator::InvalidOrderError)
        end
      end

      context 'items with same value' do
        let(:relation) { Post.order(weight: :desc, display_index: :asc) }

        it 'returns proper page' do
          # page 1
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2)
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.pluck(:weight, :display_index)).to eq [[1, 1], [1, 3]]
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'weight' => records.last.weight },
                                                                         { 'display_index' => records.last.display_index }, { 'id' => records.last.id }]
          # page 2
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2, cursor: next_cursor)
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.pluck(:weight, :display_index)).to eq [[1, 5], [0, 0]]
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'weight' => records.last.weight },
                                                                         { 'display_index' => records.last.display_index }, { 'id' => records.last.id }]
          # page 3
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2, cursor: next_cursor)
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.pluck(:weight, :display_index)).to eq [[0, 2], [0, 4]]
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'weight' => records.last.weight },
                                                                         { 'display_index' => records.last.display_index }, { 'id' => records.last.id }]
        end
      end

      context 'order by datetime' do
        let(:relation) { Post.order(posted_at: :desc) }

        it 'returns proper page' do
          # page 1
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2)
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          bd_now = BigDecimal(now.to_f.to_s)
          expect(records.map {|r| BigDecimal(r.posted_at.to_f.to_s).round(6) }).to eq [bd_now, bd_now - epsilon]
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'posted_at' => records.last.posted_at.iso8601(6) }, { 'id' => records.last.id }]
          # page 2
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2, cursor: next_cursor)
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.map {|r| BigDecimal(r.posted_at.to_f.to_s).round(6) }).to eq [bd_now - (epsilon * 2), bd_now - (epsilon * 3)]
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'posted_at' => records.last.posted_at.iso8601(6) }, { 'id' => records.last.id }]
          # page 3
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2, cursor: next_cursor)
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.map {|r| BigDecimal(r.posted_at.to_f.to_s).round(6) }).to eq [bd_now - (epsilon * 4), bd_now - (epsilon * 5)]
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'posted_at' => records.last.posted_at.iso8601(6) }, { 'id' => records.last.id }]
        end
      end

      context 'order by relation columns' do
        let(:relation) { Post.select("posts.*, authors.name as author_name").joins(:author).order('author_name desc') }

        it 'returns proper page' do
          # page 1
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2, aliases: {author_name: 'authors.name'})
          expect(page.total).to eq post_count
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.pluck(:author_name)).to eq ['author_1', 'author_1']
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'author_name' => records.last.author.name }, { 'id' => records.last.id }]
          # page 2
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2, cursor: next_cursor, aliases: {author_name: 'authors.name'})
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.pluck(:author_name)).to eq ['author_1', 'author_0']
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'author_name' => records.last.author.name }, { 'id' => records.last.id }]
        end
      end

      context 'order by relation columns' do
        let(:relation) { Post.select("posts.*, authors.name as author_name").joins(:author).order(author_name: :desc) }

        it 'returns proper page' do
          # page 1
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2, aliases: {author_name: 'authors.name'})
          expect(page.total).to eq post_count
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.pluck(:author_name)).to eq ['author_1', 'author_1']
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'author_name' => records.last.author.name }, { 'id' => records.last.id }]
          # page 2
          page = ActiveRecord::CursorPaginator.new(relation, per_page: 2, cursor: next_cursor, aliases: {author_name: 'authors.name'})
          records = page.records
          expect(records).to be_a Array
          expect(records.length).to eq 2
          expect(records.pluck(:author_name)).to eq ['author_1', 'author_0']
          next_cursor = page.end_cursor
          expect(JSON.parse(Base64.strict_decode64(next_cursor))).to eq [{ 'author_name' => records.last.author.name }, { 'id' => records.last.id }]
        end
      end
    end
  end
end
