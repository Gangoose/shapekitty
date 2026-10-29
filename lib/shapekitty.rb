# frozen_string_literal: true

require "cairo"
require_relative "shapekitty/version"
require_relative "shapekitty/error"
require_relative "shapekitty/sketch"
require_relative "shapekitty/global"

module Shapekitty
  def self.default_sketch = (@default_sketch ||= Sketch.new)

  def self.run = default_sketch.run

  def self.sketch(&block)
    s = Sketch.new
    block.arity == 1 ? block.call(s) : s.instance_eval(&block)
    s
  end

  def self.as(name)
    sketch = default_sketch
    Object.define_method(name) { sketch }
    Object.send(:private, name)
    name
  end
end
