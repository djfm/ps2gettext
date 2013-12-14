#!/usr/bin/ruby

require 'test/unit'
require_relative '../scanner.rb'

class TestStringScanner < Test::Unit::TestCase
	def test_simple
		str="hello, world, hi"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_arguments
		e = [str, %w(hello world hi)]
		assert_equal e, r
	end

	def test_quoted
		str="hello, 'world', hi"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_arguments
		e = [str, %w(hello 'world' hi)]
		assert_equal e, r
	end

	def test_quoted_2
		str="hello, world, \"hi\""
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_arguments
		e = [str, %w(hello world "hi")]
		assert_equal e, r
	end

	def test_quoted_escape
		str="hello, world, 'h\\\'i'"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_arguments
		e = [str, %w(hello world 'h\\'i')]
		assert_equal e, r
	end

	def test_quoted_escape_2
		str="\"hel\\\"lo\", world, hi"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_arguments
		e = [str, %w("hel\\"lo" world hi)]
		assert_equal e, r
	end

	def test_paren
		str="(yo(3,4))  ,   mama"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_arguments
		e = [str, %w((yo(3,4)) mama)]
		assert_equal e, r
	end

	def test_paren_str_inside
		str="(yo('3(',4))  ,   mama"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_arguments
		e = [str, ["(yo('3(',4))", "mama"]]
		assert_equal e, r
	end

	def test_paren_escaped_str_inside
		str="(yo('3\\'(',4))  ,   mama"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_arguments
		e = [str, ["(yo('3\\'(',4))", "mama"]]
		assert_equal e, r
	end

	def test_eol
		str="kikoo, lol)"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_arguments
		e = [str[0...-1], ["kikoo", "lol"]]
		assert_equal e, r
	end

	def test_eol_2
		str="(yo('3\\'(',4))  ,   mama)"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_arguments
		e = [str[0...-1], ["(yo('3\\'(',4))", "mama"]]
		assert_equal e, r
	end

	def test_until_not_in_string 
		str="x y z }"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_until_not_in_string '}'
		e = str[0...-1]
		assert_equal e, r
	end

	def test_until_not_in_string_2 
		str="x 'y}' z }"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_until_not_in_string '}'
		e = str[0...-1]
		assert_equal e, r
	end

	def test_until_not_in_string_2 
		str="x 'y}' z sprintf=[\"ab\", '}}'] }"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_until_not_in_string '}'
		e = str[0...-1]
		assert_equal e, r
	end

	def test_until_not_in_string_2 
		str="x 'y}' z sprintf=[\"ab\", '\\'}}'] }"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_until_not_in_string '}'
		e = str[0...-1]
		assert_equal e, r
	end

	def test_simple_smarty_arguments
		str="s = 4 t = 27}"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_smarty_arguments
		e = [str[0...-1], {'s' => '4', 't' => '27'}]
		assert_equal e, r
	end

	def test_trickier_smarty_arguments
		str="s = '4}' t = 27}"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_smarty_arguments
		e = [str[0...-1], {'s' => "'4}'", 't' => '27'}]
		assert_equal e, r
	end

	def test_trickier_smarty_arguments_2
		str="s = '4}' t = '2\\'7'}"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_smarty_arguments
		e = [str[0...-1], {'s' => "'4}'", 't' => "'2\\'7'"}]
		assert_equal e, r
	end

	def test_array_smarty_arguments
		str="s = 4 t = [27, 28]}"
		s = PS2Gettext::StringScanner.new (str)
		r = s.scan_smarty_arguments
		e = [str[0...-1], {'s' => '4', 't' => '[27, 28]'}]
		assert_equal e, r
	end

end