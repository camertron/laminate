require 'pry-byebug'
require 'forwardable'

module Celophane
  class MethodAlreadyDefinedError < StandardError; end
  class UnsupportedStrategyError < StandardError; end

  module Layer
    def with_layer(layer_module, options = {})
      with_layers(Array(layer_module), options)
    end

    def with_layers(layer_modules, options = {})
      # If layer_module isn't a ruby module, blow up.
      unless layer_modules.all? { |mod| mod.is_a?(Module) }
        raise ArgumentError, 'layers must all be modules'
      end

      # Grab the cache from the super class's singleton. It's not correct to
      # simply reference the @@__celophane_layer_cache variable because of
      # lexical scoping. If we were to reference the variable directly, Ruby
      # would think we wanted to associate it with the Layer module, where in
      # reality we want to associate it with each module Layer is mixed into.
      cache = self.class.class_variable_get(:@@__celophane_layer_cache)

      # We don't want to generate each wrapper class more than once, so keep
      # track of the modules => dynamic wrapper mapping and avoid re-creating
      # them on every call to with_layer.
      cache[layer_modules] ||= begin
        unless options.fetch(:allow_overrides, false)
          # Identify method collisions. In order to minimize accidental
          # monkeypatching, Celophane will error if you try to wrap an object
          # with a layer that defines any method with the same name as a method
          # the object already responds to. Starts with self, or more accurately,
          # the methods defined on self. The loop walks the ancestor chain an
          # checks each ancestor for previously defined methods.
          ancestor = self

          layer_module_methods = layer_modules.flat_map do |mod|
            mod.instance_methods(false)
          end

          while ancestor
            # Filter out Object's methods, which are common to all objects and not
            # ones we should be forwarding. Also filter out Layer's methods for
            # the same reason.
            ancestor_methods = ancestor.class.instance_methods - (
              Object.methods + Layer.instance_methods(false)
            )

            # Calculate the intersection between the layer's methods and the
            # methods defined by the current ancestor.
            already_defined = ancestor_methods & layer_module_methods

            unless already_defined.empty?
              ancestor_modules = ancestor.instance_variable_get(:@__celophane_modules)

              # @TODO: fix the English here
              raise MethodAlreadyDefinedError, "#{already_defined.join(', ')} is "\
                "already defined by one of #{ancestor_modules.map(&:name).join(', ')}"
            end

            # Grab the next ancestor and keep going. The loop exits when ancestor
            # is nil, which happens whenever the end of the ancestor chain has
            # been reached (i.e. when iteration reaches the base object).
            ancestor = ancestor.instance_variable_get(:@__celophane_ancestor)
          end
        end

        ancestor_methods = self.class.instance_methods - (
          Object.methods + Layer.instance_methods(false)
        )

        # Dynamically define a new class and mix in the layer modules. Forward
        # all the ancestor's methods to the ancestor. Dynamic layer classes keep
        # track of both the ancestor itself as well as the modules it was
        # constructed from.
        klass = Class.new do
          layer_modules.each do |layer_module|
            case options.fetch(:strategy, :include)
              when :include
                include layer_module
              when :prepend
                prepend layer_module
              else
                raise UnsupportedStrategyError,
                  "The strategy #{options[:strategy]} isn't supported"
            end
          end

          extend Forwardable

          # Forward all the ancestor's methods to the ancestor.
          def_delegators :@__celophane_ancestor, *ancestor_methods

          def initialize(ancestor, layer_modules)
            # Use absurd variable names to avoid re-defining instance variables
            # introduced by the layer module.
            @__celophane_ancestor = ancestor
            @__celophane_modules = layer_modules
          end
        end

        wrapper_name = 'With' + layer_modules.map(&:name).join('And')

        # Assign the new wrapper class to a constant inside self, with 'With'
        # prepended. For example, if the module is called Engine the wrapper
        # class will be assigned to a constant named WithEngine.
        self.class.const_set(wrapper_name, klass)
        klass
      end

      # Wrap self in a new instance of the wrapper class.
      cache[layer_modules].new(self, layer_modules)
    end

    def self.included(base)
      base.class_variable_set(:@@__celophane_layer_cache, {})
    end
  end
end

class ActiveRecordBase
  def save
    true
  end
end

class Game < ActiveRecordBase
  include Celophane::Layer

  def get_some_game_data
    :some_game_data
  end
end

module Lpis
  include Celophane::Layer

  def get_some_lpi_data
    :some_lpi_data
  end
end

module BrainAreas
  include Celophane::Layer

  def get_some_brain_area_data
    :some_brain_area_data
  end

  # def get_some_lpi_data
  #   :some_lpi_data_from_brain_areas
  # end
end

game = Game.new.with_layer(Lpis).with_layer(BrainAreas)
binding.pry
puts game.get_some_game_data
puts game.get_some_lpi_data
puts game.get_some_brain_area_data
puts game.save
