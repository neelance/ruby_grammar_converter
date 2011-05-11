$: << "../jetpeg/lib"
require "benchmark"
require "jetpeg"

class String
  def trim_parens
    if self[0] == "(" and self[-1] == ")"
      self[1..-2].trim_parens
    else
      self
    end
  end
end

class Array
  def seq
    if self.size == 1
      self.first
    else
      "(#{self.join(' ')})"
    end
  end
end

class Call
  def initialize(data)
    @name = data[:name]
    @forms = data[:forms]
  end
  
  def to_s
    parts = []
    args = []
    @forms.each_with_index do |form, i|
      if form.is_a? Value
        args << form.value
      else
        parts << "arg#{i}:#{form}"
        args << "%arg#{i}"
      end
    end
    parts << "#{@name}[#{args.join(', ')}]"
    parts.seq
  end
end

class Value
  attr_reader :value
  
  def initialize(value)
    @value = value
  end
  
  def to_s
    @value
  end
end

class Seq
  def initialize(data)
    @forms = data[:forms]
  end
  
  def parts
    list = @forms[0..-2]
    if @forms.last.is_a? Make
      list.concat @forms.last.parts
    else
      list << "@:#{@forms.last}"
    end
    list
  end
  
  def to_s
    parts.seq
  end
end

class Make
  def initialize(data)
    @forms = data[:forms]
    @cls = make_class_name(data[:name])
  end
  
  def parts
    list = []
    @forms.each_with_index do |form, i|
      list << "p#{i}:#{form}"
    end
    list << "<#{@cls}>"
    list
  end
  
  def to_s
    parts.seq
  end
end

$class_names = []
def make_class_name(name)
  cls = case name
  when "__file__"
    "CurrentFile"
  when "__line__"
    "CurrentLine"
  else
    name.split("_").map{ |part| "#{part[0].upcase}#{part[1..-1]}" }.join
  end
  $class_names << cls
  cls
end

code = IO.read "ruby.lisp.txt"
parser = data_pointer = input_address = data = result = nil

Benchmark.bm(17) do |bm|
  bm.report("loading grammar:") do
    parser = JetPEG.load File.join(File.dirname(__FILE__), "lisp_grammar.jetpeg")
  end
  bm.report("compiling:") do
    parser.optimize = false
    parser[:grammar].match "" # compile
  end
  bm.report("parsing:") do
    data_pointer, input_address = parser.match_rule_raw parser[:grammar], code
  end
  
  bm.report("loading data:") do
    data = parser[:grammar].rule_label_type.load data_pointer, code, input_address
  end
  
  bm.report("realizing data:") do
    result = JetPEG.realize_data data
  end
end

puts "parser stats: #{parser.stats}"

File.open("ruby.jetpeg", "w") do |io|
  io.write result
end

File.open("ruby_ast_nodes.rb", "w") do |io|
  io.puts "module Ruby"
  io.puts "  module AST"
  $class_names.uniq.sort.each do |name|
    io.puts "    class #{name} < Node"
    io.puts "    end"
    io.puts "    "
  end
  io.puts "  end"
  io.puts "end"
end
