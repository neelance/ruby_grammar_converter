$: << "../jetpeg/lib"
require "benchmark"
require "jetpeg"

class String
  def indent
    "  #{gsub "\n", "\n  "}"
  end
  
  def no_parens_needed
    @no_parens_needed = true
    self
  end
  
  def add_parens
    case
    when @no_parens_needed
      self
    when include?("\n")
      "(\n#{self.indent}\n)"
    else
      "( #{self} )"
    end
  end
end

class Array
  def seq
    Seq.new forms: self
  end
end

class Node
  attr_reader :data
  
  def initialize(data)
    @data = data
  end
end

class SimpleNode
  attr_reader :form
  
  def initialize(str, form, add_parens = false)
    @str = str
    @form = form
    @add_parens = add_parens
  end
  
  def generate(options = {})
    replacement = @form.generate options
    replacement = replacement.add_parens if @add_parens
    @str.sub("<form>", replacement).no_parens_needed
  end
end

class Value
  attr_reader :value
  
  def initialize(value)
    @value = value
  end
  
  def generate(options = {})
    case options[:value]
    when :explicit
      "@:#{@value}"
    when :suffix_handling
      "%value:#{@value}"
    else
      @value
    end.no_parens_needed
  end
end

class Call < Node
  def generate(options = {})
    parts = []
    args = []
    @data[:forms].each_with_index do |form, i|
      if form.is_a? Value
        args << form.value
      elsif form.is_a? Capture
        parts << form
        args << "%#{form.name}"
      else
        parts << Value.new("%arg#{i}:#{form.generate}")
        args << "%arg#{i}"
      end
    end
    parts << Value.new("#{@data[:name]}[#{args.join(', ')}]")
    parts.seq.generate options
  end
end

class Seq < Node
  def initialize(data)
    super
    raise if @data[:forms].any? { |f| f.is_a? String }
  end
  
  def follow_simple_nodes(node)
    node.is_a?(SimpleNode) ? follow_simple_nodes(node.form) : node
  end
  
  def generate(options = {})
    forms = @data[:forms].compact
    return "" if forms.empty?
    return forms.first.generate(options) if forms.size == 1
    
    value_index = -1
    if forms.last.is_a? Make
      make = forms.pop
      forms.concat make.parts
    elsif options[:value]
      value_index = forms.index { |f| follow_simple_nodes(f).is_a? AtCapture } || forms.size - 1
    end

    strings = []
    begin
      forms.each_index { |i|
        strings << forms[i].generate(options.merge(value: (i == value_index ? :explicit : false))).add_parens
      }
    rescue IllegalAtCaptureError
      strings.clear
      forms.each_index { |i|
        strings << forms[i].generate(options.merge(value: (i == value_index ? :suffix_handling : false), suffix_handling: true)).add_parens
      }
    end
    
    strings.join ' '
  end
end

class Until < Node
  def generate(options = {})
    "#{data[:repeat].generate(options)}*[#{data[:until_cond].generate(options)}]"
  end
end

class Or < Node
  def generate(options = {})
    strings = @data[:forms].map{ |f| f.generate(options) }
    simple = @data[:forms].all? { |f| f.is_a?(Value) }
    strings.join(simple ? " / " : " /\n")
  end
end

class Opt < Node
  def generate(options = {})
    if options[:suffix_handling]
      inner = "#{@data[:forms].seq.generate(value: :explicit, at_value: '%value').add_parens} /\n%value"
      "@:(\n#{inner.indent}\n)".no_parens_needed
    else
      "#{@data[:forms].seq.generate(options).add_parens}?".no_parens_needed
    end
  end
end

class Rep < Node
  def generate(options = {})
    if options[:suffix_handling]
      suffix_rule_content = "%value:#{@data[:forms].seq.generate(value: :explicit, at_value: '%inner_value').add_parens} @:( #{options[:rule_name]}_suffix[%value] / %value )"
      $additional_rules << "rule #{options[:rule_name]}_suffix[%inner_value]\n#{suffix_rule_content.indent}\nend\n"
      "@:( #{options[:rule_name]}_suffix[%value] / %value )".no_parens_needed
    else
      "#{@data[:forms].seq.generate(options).add_parens}*".no_parens_needed
    end
  end
end

class Rep1 < Node
  def generate(options = {})
    if options[:suffix_handling]
      suffix_rule_content = "%value:#{@data[:forms].seq.generate(value: :explicit, at_value: '%inner_value').add_parens} @:( #{options[:rule_name]}_suffix[%value] / %value )"
      $additional_rules << "rule #{options[:rule_name]}_suffix[%inner_value]\n#{suffix_rule_content.indent}\nend\n"
      "@:#{options[:rule_name]}_suffix[%value]".no_parens_needed
    else
      "#{@data[:forms].seq.generate(options).add_parens}+".no_parens_needed
    end
  end
end

class Capture < Node
  def name
    @data[:name]
  end
  
  def generate(options = {})
    "%#{@data[:name]}:#{@data[:form].generate(options).add_parens}".no_parens_needed
  end
end

class AtCapture < Node
  def generate(options = {})
    raise IllegalAtCaptureError if not options[:value]
    @data[:form].generate(options)
  end
end

class AtValue < Node
  def generate(options = {})
    options[:at_value] || "<fixme>"
  end
end

class IllegalAtCaptureError < RuntimeError
end

class Make < Node
  def parts
    @parts ||= begin
      list = []
      @data[:forms].each_with_index do |form, i|
        list << SimpleNode.new("p#{i}:<form>", form)
      end
      list << Value.new("<#{make_class_name(@data[:name])}>")
      list
    end
  end
  
  def generate(options = {})
    parts.seq.generate(options)
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

$rule_replacements = {}

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
    data_pointer, input_address = parser.match_rule parser[:grammar], code, :output => :pointer
  end
  
  bm.report("loading data:") do
    data = parser[:grammar].rule_label_type.load data_pointer, code, input_address
  end
  
  bm.report("realizing data:") do
    $additional_rules = []
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

#parser.mod.dump