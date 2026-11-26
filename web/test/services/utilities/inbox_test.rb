require "test_helper"

class Utilities::InboxTest < ActiveSupport::TestCase
  # Gmail's search as far as Utilities::Inbox uses it: the ids of the messages delivered to any of
  # the addresses a query names, newest first, a page at a time. Remembers each query.
  class FakeGmail
    Page = Data.define(:messages, :next_page_token)
    Message = Data.define(:id)

    attr_reader :queries

    # messages: [id, addresses it was delivered to], oldest first
    def initialize(messages)
      @messages = messages
      @queries = []
    end

    def list_user_messages(_user, q:, max_results:, page_token: nil)
      @queries << q
      named = q[/\A\{(.*)\}/, 1].split.map { it.delete_prefix("deliveredto:") }
      ids = @messages.select { |_, to| to.intersect?(named) }.map(&:first).reverse
      start = page_token.to_i
      Page.new(messages: ids.drop(start).first(max_results).map { Message.new(id: it) },
        next_page_token: ids.size > start + max_results ? (start + max_results).to_s : nil)
    end
  end

  def address(n) = "household.bills+h#{n}-#{n.to_s.rjust(10, "0")}@gmail.com"

  test "searches a bounded number of addresses at a time and finds every ledger's mail" do
    addresses = (1..45).map { address(it) }
    gmail = FakeGmail.new(addresses.map { [ "m-#{it}", [ it ] ] })

    ids = Utilities::Inbox.new(gmail).unprocessed(addresses)

    assert_equal 3, gmail.queries.size
    assert gmail.queries.all? { it.scan("deliveredto:").size <= Utilities::Inbox::ADDRESSES_PER_SEARCH }
    assert gmail.queries.all? { it.end_with?("} -label:household-tracker-processed") }
    assert_equal addresses.map { "m-#{it}" }.sort, ids.sort
  end

  test "a ledger's messages come oldest first, and one delivered to addresses in two searches comes once" do
    addresses = (1..25).map { address(it) }
    first, last = addresses.first, addresses.last
    gmail = FakeGmail.new([ [ "old", [ first ] ], [ "both", [ first, last ] ], [ "new", [ first ] ], [ "late", [ last ] ] ])

    assert_equal %w[old both new late], Utilities::Inbox.new(gmail).unprocessed(addresses)
    assert_equal 2, gmail.queries.size
  end

  test "one search still reads several pages" do
    gmail = FakeGmail.new((1..250).map { [ format("m%03d", it), [ address(1) ] ] })

    assert_equal (1..250).map { format("m%03d", it) }, Utilities::Inbox.new(gmail).unprocessed([ address(1) ])
    assert_equal 3, gmail.queries.size
  end

  test "no address, no search" do
    gmail = FakeGmail.new([])

    assert_equal [], Utilities::Inbox.new(gmail).unprocessed([])
    assert_empty gmail.queries
  end
end
