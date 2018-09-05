#
# Ruby circuit simulation classes.  This file contains a base class Gate,
# and several derived classes describing digital logic gates.  There are
# also classes for input and display.  There's also a flip-flop.
#

class Gate 
  # This is a count of the "active" gates, which are ones which have received
  # a signal but not resolved it.
  @@active = 0

  # This is a list of gates which have registered that they want to be
  # notified when the circuit is quiet.  They give an integer priority,
  # and are notified in increasing priority order.
  @@needquiet = { }
  def quiet_register(pri)
    if ! @@needquiet.key?(pri) then @@needquiet[pri] = [ ] end
    @@needquiet[pri].push(self)
  end

  # Here's how we set stuff.  There are static and object versions of
  # each, since I may want to activate from other spots.
  def Gate.activate
    @@active += 1
  end
  def activate
    Gate.activate
  end
  def Gate.deactivate
    @@active -= 1
    if @@active == 0 then
      @@needquiet.keys.sort.each \
      		{ |p| @@needquiet[p].each { |g| g.onquiet } }
    end
  end
  def deactivate
    Gate.deactivate
  end

  # This is the default quiet action (nothing).
  def onquiet
  end

  # A signal is directed to a particular port on a particular gate.  This
  # encapsulates those two data.  When a gate connects to us, we send back
  # one of these to direct its later signal changes.
  class LinkHandle
    def initialize(sink_gate, sink_port)
      @sinkg = sink_gate
      @sinkp = sink_port
    end

    # The sending gate uses this method to forward the signal to the
    # downstream gate.
    def signal(value)
      @sinkg.signal(@sinkp,value)
    end

    attr_reader :sinkg, :sinkp
  end

  def initialize(ival = false)
    @inputs = [ ]	# Array of inputs (boolean values)
    @outputs = [ ]	# Array of LinkHandle objects where to send output
    @outval = ival	# Present output value.
  end

  # This is called when a input gate sends us a signal on a particular input.
  # We recompute our output value, and, if it changes, we send it on to all
  # of our outbound connections.
  def signal(port, val)
    # The derived class needs to implement the value method.
    self.activate
    @inputs[port] = val
    newval = self.value
    if newval != @outval then
      @outval = newval
      @outputs.each { | c | c.signal(newval) }
    end
    self.deactivate
  end

  # Call this to connect your output to the next one of our inputs.
  def connect(v)
    port = @inputs.length
    @inputs.push(v)
    c = LinkHandle.new(self, port)
    self.signal(port, v)
    return c
  end

  # Join me to another gate.
  def join(g)
    @outputs.push(g.connect(@outval))
  end
  def joinmany(*p)
    p.each { |i| self.join(i); }
  end

  attr_reader :outval

  # Some printing help
  def name
    return self.class.to_s
  end
  def insstr
    return (if @inputs.length == 0 then "-" else @inputs.join('.') end)
  end
  def to_s
    return name + " " + insstr + " => " + @outval.to_s
  end

  # Create another object of the same type.  
  def another
    return self.class.new
  end
  def manyothers(n)
    ret = []
    n.times { ret.push(self.another) }
    return ret
  end

  # This manufactures any number of objects.  It is a static method, and
  # inherited by the real gates.  The expression self.new, then, runs the
  # new method on the actual object, which the inheriting class.  Therefore,
  # it will create any gate.
  def Gate.many(n)
    ret = [ ]
    n.times { ret.push(self.new) }
    return ret
  end
  
  # Dump a whole circuit.  Yecch.
  def outlinks
    return @outputs
  end
  def Gate.dump(*roots)
    ct = -1
    gatemap = { }
    for g in roots
      gatemap[g] = (ct += 1) unless gatemap.has_key?(g)
    end

    printed = { }
    while roots.length > 0 
      g = roots.shift 
      next if printed.has_key?(g)
      print "[", gatemap[g], "] ", g, ":"
      for c in g.outlinks
        og = c.sinkg
        gatemap[og] = (ct += 1) unless gatemap.has_key?(og)
        print " ", gatemap[og], "@", c.sinkp
        roots.push(og)
      end
      print " [none]" if g.outlinks.length <= 0
      print "\n"
      printed[g] = true
    end
  end
end

# Standard and gate
class AndGate < Gate
  def initialize
    super(true)
  end
  def value
    for i in @inputs
      return false if !i
    end
    return true
  end
end
class NandGate < AndGate
  def value
    return ! super
  end
end

# Standard or gate
class OrGate < Gate
  def value
    for i in @inputs
      return true if i
    end
    return false
  end
end
class NorGate < OrGate
  def value
    return ! super
  end
end

# Standard xor gate
class XorGate < Gate
  def value
    ret = false
    for i in @inputs
      ret ^= i
    end
    return ret
  end
end

# Gates with a limited number of input connections.
class LimitedGate < Gate
  def initialize(max=1,i=false)
    super(i)
    @max = max
  end

  # Enforce connect limit.
  def connect(v)
    if @inputs.length >= @max then
      raise TypeError.new("Too many input connections.")
    end
    super(v)
  end
  
end

# Not gate.
class NotGate < LimitedGate
  def initialize
    super(1,true)
  end
  def value
    return ! @inputs[0]
  end
end

# This is a "yes gate" or amplifier.  It just forwards its input to all its
# outputs
class Connector < LimitedGate
  def value
    return @inputs[0]
  end

  # We can also use it as a one-bit input device.
  def send(v)
    self.signal(0,v)
  end
end

# D Flip-Flop.  Level-triggered.  First input is D, second is clock.
class FlipFlop < LimitedGate
  def initialize
    super(2)
  end
  def value
    return (if @inputs[1] then @inputs[0] else @outval end)
  end
end

# D Flip-Flop.  Edge-triggered.  First input is D, second is clock.
# I think the level-triggered might make a lot more sense with this
# simulation, though these are better in circuits.  
class FlipFlopET < FlipFlop
  def initialize
    super
    @newval = false
  end
  def value
    return @newval
  end
  def signal(port, val)
    # Need to stick our fingers in this thing to find the rising edge.
    self.activate
    @newval = 
      if port == 1 && !@inputs[1] && val then @inputs[0] else @outval  end
    super(port,val)
    self.deactivate
  end
end

# Simple test point
class Tester < LimitedGate
  def initialize(name="Tester")
    super(1)
    @name = name
  end
  attr_writer :name
  def value
    print @name, ": ", if @inputs[0] then "on" else "off" end, "\n";
    return @inputs[0]
  end
end

# Numeric output device.  Connect lines starting with LSB.
class NumberOut < Gate
  @@quiet = false
  def NumberOut.shush(q=true)
    @@quiet = q
  end

  def initialize(name="Value", pri = 1)
    @name = name
    quiet_register(pri)
    super()
  end

  attr_writer :name

  # Print the value on quiet.
  def onquiet
    return if @@quiet;

    val = 0
    @inputs.reverse_each { |i| 
      val <<= 1
      if i then
        val |= 1
      end
    }

    print @name, ": ", val, "\n"
  end
  def value
    return false
  end
end

# LED which prints when circuit becomes quiet.
class LED < NumberOut
  def initialize(name="LED", pri = 1)
    super(name, pri)
  end
  def onquiet
    if @inputs.length > 0 && ! @@quiet then
      print @name, ": ", if @inputs[0] then "on" else "off" end, "\n"
    end
  end
  def connect(v)
    if @inputs.length >= 1 then
      raise TypeError.new("Too many input connections.")
    end
    super(v)
  end
end

# Base for input devices.  Mostly deals will collecting connections.
class InputDevice
  def initialize
    @targs = []
  end

  # Add a connection
  def join(g)
    @targs.push(g.connect(false))
  end
  def joinmany(*p)
    p.each { |i| self.join(i); }
  end

  def outlinks
    return @targs
  end

end

# Switch bank.  Connects to any number of gates, and will feed them a
# binary number (as a string).  Connections start with LSB.  Initially,
# all the switches are off.
class SwitchBank < InputDevice

  # Send a number.  Can take an integer or a string.
  def set(n)
    if n.is_a?(TrueClass) || n.is_a?(FalseClass) then
      @targs.each { | x | x.signal(n) }
    elsif n.is_a?(Integer) then
      @targs.each { | x | x.signal(n&1 == 1); n >>= 1 }
    else
      # Assume n is an ascii string of 1's and 0's.
      if n.length < @targs.length then
        n = ('0' * (@targs.length - n.length)) + n
      end
      sub = n.length - 1
      @targs.each { | x | x.signal(n[sub].chr != "0"); sub -= 1 }
    end
  end

  # This is like switch, but it keeps the circuit active during each
  # sending.
  def value=(n)
    Gate.activate
    self.set(n)
    Gate.deactivate
  end

end

# Send a pulse (clock tick?)
class Pulser < InputDevice
  
  def pulse
    Gate.activate
    @targs.each { |t| t.signal(true); }
    @targs.each { |t| t.signal(false); }
    Gate.deactivate
  end
end
