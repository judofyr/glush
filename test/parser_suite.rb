ParserSuite = proc do
  let(:parser) do
    @parser ||= create_parser(grammar)
  end

  def self.assert_recognize(input)
    it "should recognize" do
      assert parser.recognize?(input), "expected match for input: #{input}"
    end
  end

  def self.refute_recognize(input)
    it "should not recognize" do
      refute parser.recognize?(input), "expected no match for input: #{input}"
    end
  end

  def self.assert_marks(input, marks)
    it "should match marks" do
      skip unless parser.respond_to?(:parse)
      result = parser.parse(input).unwrap
      assert_equal marks, result.marks.map(&:to_a)
    end
  end

  describe(:paren) do
    let(:grammar) { TestGrammars.paren }

    assert_recognize ""
    refute_recognize "("
    assert_recognize "()"
    assert_recognize "(())"
  end

  describe(:empty_left_recursion) do
    let(:grammar) { TestGrammars.empty_left_recursion }

    assert_recognize ""
    assert_recognize "+"
    assert_recognize "++"
    refute_recognize "++-"
  end

  describe(:super_ambigous) do
    let(:grammar) { TestGrammars.super_ambigous }

    assert_recognize "a"
    assert_recognize "aa"
    assert_recognize "aaa"
    assert_recognize "aaaa"
    assert_recognize "aaaaa"
    assert_recognize "aaaaaa"
  end

  describe(:three_a) do
    let(:grammar) { TestGrammars.three_a }

    assert_recognize "a"
    refute_recognize "aa"
    assert_recognize "aaa"
    refute_recognize "aaaa"
    assert_recognize "aaaaa"
  end

  describe(:amb_expr) do
    let(:grammar) { TestGrammars.amb_expr }

    assert_recognize "n"
    assert_recognize "n+n"
    assert_recognize "n+n*n/n-n*n-n"
    refute_recognize "n+n*n/n-nn-n"
  end

  describe(:manual_expr) do
    let(:grammar) { TestGrammars.manual_expr }

    assert_recognize "n"
    assert_recognize "n+n"
    assert_recognize "n*n"
    assert_recognize "n+n*n/n-n*n-n"
    refute_recognize "n+n*n/n-nn-n"

    assert_marks "n", [[:n, 0]]
    assert_marks "n+n", [[:add, 0], [:n, 0], [:n, 2]]
    assert_marks "n+n*n+n", [
      [:add, 0],
        [:add, 0],
          [:n, 0],
          [:mul, 2],
            [:n, 2],
            [:n, 4],
        [:n, 6]
    ]
  end

  describe(:comments) do
    let(:grammar) { TestGrammars.comments }

    assert_recognize "aa"
    assert_recognize "a#\n"
    assert_recognize "a#anything!🎉\naa"
    assert_recognize "a#anything!🎉\na#more\n"
    refute_recognize "a#"
  end

  describe("re-used patterns") do
    let(:grammar) do
      Glush::DSL.build {
        def_rule :main do
          foo = str("a")
          foo >> foo >> foo
        end

        main
      }
    end

    refute_recognize "a"
    refute_recognize "aa"
    assert_recognize "aaa"
    refute_recognize "aaaa"
  end

  describe("precedence") do
    let(:grammar) { TestGrammars.prec_expr }

    assert_recognize "n"
    assert_recognize "n+n"
    assert_recognize "n+n+n"
    assert_marks "n+n+n", [
      [:add, 0],
        [:add, 0],
          [:n, 0],
          [:n, 2],
        [:n, 4],
    ]

    assert_marks "n+n-n", [
      [:sub, 0],
        [:add, 0],
          [:n, 0],
          [:n, 2],
        [:n, 4],
    ]

    assert_marks "n^n^n", [
      [:pow, 0],
        [:n, 0],
        [:pow, 2],
          [:n, 2],
          [:n, 4],
    ]
  end

  describe("any") {
    let(:grammar) {
      Glush::DSL.build {
        def_rule :s do
          str("a") >> anytoken
        end

        s
      }
    }

    assert_recognize "ab"
    assert_recognize "aa"
    refute_recognize "aaa"
  }

  describe("nested tail call") {
    let(:grammar) {
      Glush::DSL.build {
        def_rule :s do
          str("s") >> b
        end

        def_rule :b do
          str("b") >> a
        end

        def_rule :a do
          str("a")
        end

        s
      }
    }

    assert_recognize "sba"
    refute_recognize "sb"
  }

  describe("tail recursive alias") {
    let(:grammar) {
      Glush::DSL.build {
        def_rule :s do
          str("s") >> a
        end

        def_rule :a do
          b
        end

        def_rule :b do
          str("b")
        end

        s
      }
    }

    assert_recognize "sb"
  }

  describe("non-rule entry") {
    let(:grammar) {
      Glush::DSL.build {
        def_rule :s do
          str("1")
        end

        str("a") >> s >> str("b")
      }
    }

    assert_recognize "a1b"
  }

  describe("basic left recursive") {
    let(:grammar) {
      Glush::DSL.build {
        def_rule :a do
          b >> str("a")
        end

        def_rule :b do
          c >> str("b")
        end

        def_rule :c do
          str("c")
        end

        def_rule :a_indirect do
          a
        end

        str("s") >> a_indirect >> str("s")
      }
    }

    assert_recognize "scbas"
  }

  describe("mixed recursive") {
    let(:grammar) {
      Glush::DSL.build {
        def_rule :a do
          str("a") >> b
        end

        def_rule :b do
          c >> str("b")
        end

        def_rule :c do
          str("c")
        end

        a
      }
    }

    assert_recognize "acb"
  }

  describe("mixed nested recursive") {
    let(:grammar) {
      Glush::DSL.build {
        def_rule :a do
          str("a") >> b
        end

        def_rule :b do
          c >> str("b")
        end

        def_rule :c do
          d >> str("c")
        end

        def_rule :d do
          str("d")
        end

        a
      }
    }

    assert_recognize "adcb"
    refute_recognize "adc"
  }

  describe("error reporting") {
    let(:grammar) { TestGrammars.prec_expr }
    before { skip if !parser.respond_to?(:parse) }

    it "report errors on n" do
      result = parser.parse("n*n+n++n")
      assert result.error?
      assert_equal 6, result.position
    end

    it "report errors on ops" do
      result = parser.parse("n*n+n +n")
      assert result.error?
      assert_equal 5, result.position
    end

    it "reports errors on eof" do
      result = parser.parse("n*n+n+")
      assert result.error?
      assert_equal 6, result.position
    end

    it "can extract marks from result" do
      result = parser.parse("n*n")
      refute result.error?
      assert result.marks
    end
  }
end

