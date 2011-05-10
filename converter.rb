$: << "../jetpeg/lib"
require "benchmark"
require "jetpeg"

class String
  def rp
    if self[0] == "(" and self[-1] == ")"
      self[1..-2]
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

code = IO.read "ruby.lisp.txt"
parser = nil
data = nil
result = nil

Benchmark.bm(17) do |bm|
  bm.report("loading grammar:") do
    parser = JetPEG.load File.join(File.dirname(__FILE__), "lisp_grammar.jetpeg")
  end
  bm.report("compiling:") do
    parser.optimize = false
    parser.parse "" # compile
  end
  bm.report("parsing:") do
    data = parser.parse(code)
  end
  bm.report("realizing data:") do
    result = JetPEG.realize_data data
  end
end

puts "parser stats: #{parser.stats}"

File.open("ruby.jetpeg", "w") do |io|
  io.write result
end
