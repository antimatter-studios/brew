# typed: strict
# frozen_string_literal: true

# A `Tapfile` allows a tap repository to declare which of its paths Homebrew
# materialises on disk when the tap is cloned or updated. This lets large
# repositories (e.g. monorepos doubling as their own tap) serve only their
# tap-relevant contents to users.
#
# A `Tapfile` lives at the root of the tap repository and contains a single
# `tap_filter` block, which is called with each repository-relative path and
# returns whether that path should be materialised:
#
# ```ruby
# tap_filter do |path|
#   path.start_with?("Formula/")
# end
# ```
class Tapfile
  # Error raised when a `Tapfile` cannot be evaluated or does not define a
  # `tap_filter` block.
  class Error < RuntimeError; end

  Filter = T.type_alias { T.proc.params(path: String).returns(T.untyped) }

  # The minimal context `Tapfile` contents are evaluated in, exposing only
  # the `tap_filter` DSL method.
  class DSL
    sig { returns(T.nilable(Filter)) }
    attr_reader :filter

    sig { void }
    def initialize
      @filter = T.let(nil, T.nilable(Filter))
    end

    sig { params(block: T.nilable(Filter)).void }
    def tap_filter(&block)
      raise Error, "`tap_filter` requires a block." if block.nil?
      raise Error, "`tap_filter` may only be defined once." unless @filter.nil?

      @filter = block
    end
  end
  private_constant :DSL

  # Evaluate `Tapfile` contents and return a {Tapfile} wrapping its filter.
  #
  # @raise [Tapfile::Error] if the contents raise or define no `tap_filter`.
  sig { params(contents: String, source: String).returns(Tapfile) }
  def self.parse(contents, source: "Tapfile")
    dsl = DSL.new
    begin
      dsl.instance_eval(contents, source, 1)
    rescue Error
      raise
    rescue ScriptError, StandardError => e
      raise Error, "#{source} could not be evaluated: #{e.message}"
    end

    filter = dsl.filter
    raise Error, "#{source} does not define a `tap_filter` block." if filter.nil?

    new(filter)
  end

  sig { params(filter: Filter).void }
  def initialize(filter)
    @filter = T.let(filter, Filter)
  end

  # Whether the repository-relative `path` should be materialised.
  sig { params(path: String).returns(T::Boolean) }
  def include?(path)
    !!@filter.call(path)
  end
end
