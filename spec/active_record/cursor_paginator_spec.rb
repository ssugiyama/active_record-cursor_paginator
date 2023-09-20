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
    Temping.teardown
    Temping.create(:post) do
      with_columns do |t|
        t.integer :display_index
      end
    end
  end

  context 'paginator' do
    let!(:post_count) { 6 }
    let(:relation) { Post.order(display_index: :desc) }

    before do
      (0...post_count).each do |i|
        Post.create(display_index: i)
      end
    end

    context 'bidirectional' do
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
        it 'raises error' do
          expect { ActiveRecord::CursorPaginator.new(relation, per_page: 2, cursor: 'invalid').records }.
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
    end
  end
end
