# typed: true
# frozen_string_literal: true

require "tapfile"

RSpec.describe Tapfile do
  describe ".parse" do
    it "reads gitignore-style patterns, ignoring blank lines and comments" do
      expect(described_class.parse("/Formula/\n").patterns).to eq ["/Formula/"]
      # No trailing newline.
      expect(described_class.parse("/Formula/").patterns).to eq ["/Formula/"]
      expect(described_class.parse("  /Formula/  \n").patterns).to eq ["/Formula/"]
      expect(described_class.parse("/Formula/\n/Casks/\n").patterns).to eq ["/Formula/", "/Casks/"]
      expect(described_class.parse("\n/Formula/\n\n\n/Casks/\n").patterns).to eq ["/Formula/", "/Casks/"]
      expect(described_class.parse("# only formulae\n/Formula/\n").patterns).to eq ["/Formula/"]
      expect(described_class.parse("  # indented\n/Formula/\n").patterns).to eq ["/Formula/"]
      expect(described_class.parse("/Formula/\n!/Formula/internal/\n").patterns)
        .to eq ["/Formula/", "!/Formula/internal/"]
      # Contents are data, never evaluated.
      expect(described_class.parse('raise "boom"').patterns).to eq ['raise "boom"']
    end

    it "raises when no patterns are declared" do
      expect { described_class.parse("") }.to raise_error Tapfile::Error
    end

    it "raises when only comments and blank lines are declared" do
      expect { described_class.parse("# nothing\n\n") }.to raise_error Tapfile::Error
    end

    it "names the source in the error" do
      expect { described_class.parse("", source: "some/Tapfile") }
        .to raise_error Tapfile::Error, %r{some/Tapfile}
    end
  end

  describe "#sparse_checkout" do
    it "writes one pattern per line, always materialising the Tapfile itself" do
      expect(described_class.parse("/Formula/\n/Casks/\n").sparse_checkout)
        .to eq "/Formula/\n/Casks/\n/Tapfile\n"
    end
  end
end
