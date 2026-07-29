# typed: strict
# frozen_string_literal: true

# A `Tapfile` allows a tap repository to declare which of its paths Homebrew
# materialises on disk when the tap is cloned or updated. This lets large
# repositories (e.g. monorepos doubling as their own tap) serve only their
# tap-relevant contents to users.
#
# A `Tapfile` lives at the root of the tap repository and holds `gitignore`-style
# patterns, one per line. Blank lines and `#` comments are ignored. Patterns are
# handed to Git's sparse checkout unchanged, so anything `gitignore(5)` accepts
# works, including `!` negation and `/` anchoring to the repository root:
#
# ```
# /Formula/
# !/Formula/internal/
# ```
#
# Patterns are data and are never evaluated: they only select which of the
# repository's own tracked paths Git materialises, so a `Tapfile` cannot name
# anything outside the tap.
class Tapfile
  # Error raised when a `Tapfile` declares no usable patterns.
  class Error < RuntimeError; end

  sig { returns(T::Array[String]) }
  attr_reader :patterns

  # Parse `Tapfile` contents into the patterns it declares.
  #
  # @raise [Tapfile::Error] if the contents declare no patterns.
  sig { params(contents: String, source: String).returns(Tapfile) }
  def self.parse(contents, source: "Tapfile")
    patterns = contents.lines.filter_map do |line|
      pattern = line.strip
      next if pattern.empty? || pattern.start_with?("#")

      pattern
    end

    raise Error, "#{source} declares no patterns." if patterns.empty?

    new(patterns)
  end

  sig { params(patterns: T::Array[String]).void }
  def initialize(patterns)
    @patterns = patterns
  end

  # The `.git/info/sparse-checkout` body for these patterns. The `Tapfile`
  # itself is always materialised so that a later update can re-read it.
  sig { returns(String) }
  def sparse_checkout
    (patterns + ["/Tapfile"]).map { |pattern| "#{pattern}\n" }.join
  end
end
