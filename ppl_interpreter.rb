#!/usr/bin/env ruby
# ppl.rb
# A simple interpreter for the Plain Programming Language (PPL) with linked lists.

# ---------------- Linked list implementation ----------------
class Node
  attr_accessor :value, :next

  def initialize(value = nil)
    @value = value
    @next = nil
  end
end

class LinkedList
  include Enumerable

  attr_accessor :head

  def initialize
    @head = nil
  end

  def each
    current = @head
    while current
      yield current.value
      current = current.next
    end
  end

  def empty?
    @head.nil?
  end

  # Prepend a value as the new first element
  def prepend(value)
    node = Node.new(value)
    node.next = @head
    @head = node
    self
  end

  # Append (useful for constructing deep copies)
  def append(value)
    node = Node.new(value)
    if @head.nil?
      @head = node
    else
      current = @head
      current = current.next while current.next
      current.next = node
    end
    self
  end

  # Return the first element's value (or nil)
  def head_value
    @head&.value
  end

  # Return a LinkedList containing all elements but the first
  def tail_list
    tail = LinkedList.new
    return tail if @head.nil?
    current = @head.next
    while current
      tail.append(deep_clone_value(current.value))
      current = current.next
    end
    tail
  end

  # Convert to Ruby Array of values (for display & copying convenience)
  def to_a
    arr = []
    each { |v| arr << v }
    arr
  end

  # deep copy of the linked list (including recursively copying any nested LinkedLists)
  def deep_copy
    copy = LinkedList.new
    return copy if @head.nil?
    # We need to preserve original order. We'll collect values then append their deep clones.
    values = to_a
    values.each { |v| copy.append(deep_clone_value(v)) }
    copy
  end

  def to_s
    "[" + to_a.map { |v| display_value(v) }.join(", ") + "]"
  end

  private

  def deep_clone_value(val)
    # If it's a LinkedList, call its deep_copy; if it's an Integer, return int; else fallback to Marshal
    if val.is_a?(LinkedList)
      val.deep_copy
    elsif val.is_a?(Integer)
      val
    else
      # Generic deep clone (should rarely be needed)
      Marshal.load(Marshal.dump(val))
    end
  end

  def display_value(v)
    if v.is_a?(LinkedList)
      v.to_s
    else
      v.inspect
    end
  end
end

# ---------------- Symbol environment ----------------
class Environment
  # symbol table entries: name -> { type: :int/:list, value: ... }
  def initialize
    @symbols = {}
  end

  def declare_integer(name)
    raise "Identifier '#{name}' already declared" if @symbols.key?(name)
    @symbols[name] = { type: :int, value: 0 }
  end

  def declare_list(name)
    raise "Identifier '#{name}' already declared" if @symbols.key?(name)
    @symbols[name] = { type: :list, value: LinkedList.new }
  end

  def assigned?(name)
    @symbols.key?(name)
  end

  def get_entry(name)
    entry = @symbols[name]
    raise "Undefined identifier '#{name}'" unless entry
    entry
  end

  def value_of(name)
    get_entry(name)[:value]
  end

  def type_of(name)
    get_entry(name)[:type]
  end

  # assign integer value (from ASSIGN or HEAD)
  def assign_int(name, int_val)
    entry = get_entry(name)
    raise "Type error: '#{name}' is not declared as INTEGER" unless entry[:type] == :int
    raise "Expected integer value for '#{name}'" unless int_val.is_a?(Integer)
    entry[:value] = int_val
  end

  # bind a list value to name (COPY, TAIL, or HEAD when element is a list)
  def assign_list(name, list_val)
    entry = get_entry(name)
    raise "Type error: '#{name}' is not declared as LIST" unless entry[:type] == :list
    raise "Expected LinkedList for '#{name}'" unless list_val.is_a?(LinkedList)
    entry[:value] = list_val
  end

  # general setter that decides appropriately (used rarely)
  def set(name, value)
    entry = get_entry(name)
    if entry[:type] == :int
      raise "Cannot set non-integer to INTEGER '#{name}'" unless value.is_a?(Integer)
      entry[:value] = value
    else
      raise "Cannot set non-list to LIST '#{name}'" unless value.is_a?(LinkedList)
      entry[:value] = value
    end
  end

  def to_s
    lines = @symbols.map do |name, entry|
      val_repr = entry[:type] == :list ? entry[:value].to_s : entry[:value].inspect
      "#{name} (#{entry[:type]}) = #{val_repr}"
    end
    lines.join("\n")
  end
end

# ---------------- Interpreter ----------------
class Interpreter
  def initialize(filename)
    @lines = File.readlines(filename, chomp: true)
    @env = Environment.new
    @pc = 0
    @halted = false
  end

  def run
    while @pc < @lines.size && !@halted
      line = @lines[@pc]
      begin
        result = execute(line)
        # result may be :halt (stop), :jump => new pc integer, or nil (advance normally)
        case result
        when :halt
          @halted = true
        when Integer
          @pc = result
        else
          @pc += 1
        end
      rescue => e
        puts "Runtime error at line #{@pc + 1}:"
        puts "  >> #{@lines[@pc].strip}"
        puts "  Error: #{e.message}"
        break
      end
    end

    puts "\nFinal state:"
    puts @env
  end

  def execute(raw_line)
    line = raw_line.to_s.sub(/#.*/, '').strip
    return nil if line.empty?

    parts = line.split
    cmd = parts[0].upcase
    args = parts[1..-1] || []

    case cmd
    when 'INTEGER'
      ensure_args!(args, 1)
      @env.declare_integer(args[0])
      nil
    when 'LIST'
      ensure_args!(args, 1)
      @env.declare_list(args[0])
      nil
    when 'MERGE'
      ensure_args!(args, 2)
      merge(args[0], args[1])
      nil
    when 'COPY'
      ensure_args!(args, 2)
      copy(args[0], args[1])
      nil
    when 'HEAD'
      ensure_args!(args, 2)
      head(args[0], args[1])
      nil
    when 'TAIL'
      ensure_args!(args, 2)
      tail(args[0], args[1])
      nil
    when 'ASSIGN'
      ensure_args!(args, 2)
      assign_const(args[0], args[1])
      nil
    when 'CHS'
      ensure_args!(args, 1)
      chs(args[0])
      nil
    when 'ADD'
      ensure_args!(args, 2)
      add(args[0], args[1])
      nil
    when 'IF'
      ensure_args!(args, 2)
      conditional(args[0], args[1])
    when 'PRINT'
      ensure_args!(args, 1)
      print_value(args[0])
      nil
    when 'PRINTALL'
      puts "---- Environment ----"
      puts @env
      nil
    when 'HLT'
      :halt
    else
      raise "Unknown instruction: #{cmd}"
    end
  end

  private

  def ensure_args!(args, n)
    raise "Wrong argument count (expected #{n}, got #{args.length})" unless args.length == n
  end

  # ---------- Instruction helpers ----------
  def merge(src_name, dest_name)
    raise "Undefined identifier '#{src_name}'" unless @env.assigned?(src_name)
    raise "Undefined identifier '#{dest_name}'" unless @env.assigned?(dest_name)

    src_entry = @env.get_entry(src_name)
    dest_entry = @env.get_entry(dest_name)

    raise "MERGE target '#{dest_name}' is not a LIST" unless dest_entry[:type] == :list

    # We need to insert a deep copy of src value as the first element of dest list.
    val_copy = deep_clone_symbol_value(src_entry)
    dest_list = dest_entry[:value]
    dest_list.prepend(val_copy)
    nil
  end

  def copy(src_name, dst_name)
    raise "Undefined identifier '#{src_name}'" unless @env.assigned?(src_name)
    raise "Undefined identifier '#{dst_name}'" unless @env.assigned?(dst_name)

    src_entry = @env.get_entry(src_name)
    dst_entry = @env.get_entry(dst_name)

    raise "COPY source '#{src_name}' is not a LIST" unless src_entry[:type] == :list
    raise "COPY destination '#{dst_name}' is not a LIST" unless dst_entry[:type] == :list

    dst_entry[:value] = src_entry[:value].deep_copy
    nil
  end

  def head(list_name, id_name)
    raise "Undefined identifier '#{list_name}'" unless @env.assigned?(list_name)
    raise "Undefined identifier '#{id_name}'" unless @env.assigned?(id_name)

    list_entry = @env.get_entry(list_name)
    id_entry = @env.get_entry(id_name)

    raise "HEAD source '#{list_name}' is not a LIST" unless list_entry[:type] == :list

    first = list_entry[:value].head_value
    raise "HEAD on empty list '#{list_name}'" if first.nil?

    # If the first element is an integer, assign to integer variable; if list, assign to list variable.
    if first.is_a?(Integer)
      raise "Type mismatch: trying to bind integer to LIST '#{id_name}'" if id_entry[:type] != :int
      id_entry[:value] = first
    elsif first.is_a?(LinkedList)
      raise "Type mismatch: trying to bind list to INTEGER '#{id_name}'" if id_entry[:type] != :list
      id_entry[:value] = first.deep_copy
    else
      # Shouldn't happen in normal PPL, but handle generically
      if id_entry[:type] == :int
        raise "HEAD first element is not an integer"
      else
        raise "HEAD first element is not a list"
      end
    end
    nil
  end

  def tail(list1_name, list2_name)
    raise "Undefined identifier '#{list1_name}'" unless @env.assigned?(list1_name)
    raise "Undefined identifier '#{list2_name}'" unless @env.assigned?(list2_name)

    entry1 = @env.get_entry(list1_name)
    entry2 = @env.get_entry(list2_name)

    raise "TAIL source '#{list1_name}' is not a LIST" unless entry1[:type] == :list
    raise "TAIL destination '#{list2_name}' is not a LIST" unless entry2[:type] == :list

    entry2[:value] = entry1[:value].tail_list
    nil
  end

  def assign_const(name, value_str)
    raise "Undefined identifier '#{name}'" unless @env.assigned?(name)
    entry = @env.get_entry(name)
    raise "ASSIGN target '#{name}' is not INTEGER" unless entry[:type] == :int
    # Interpret value_str as integer literal (spec says integer constant)
    if value_str =~ /\A-?\d+\z/
      entry[:value] = value_str.to_i
    else
      raise "ASSIGN expects integer constant, got '#{value_str}'"
    end
    nil
  end

  def chs(var)
    raise "Undefined identifier '#{var}'" unless @env.assigned?(var)
    entry = @env.get_entry(var)
    raise "CHS target '#{var}' is not INTEGER" unless entry[:type] == :int
    entry[:value] = -entry[:value]
    nil
  end

  def add(a, b)
    raise "Undefined identifier '#{a}'" unless @env.assigned?(a)
    raise "Undefined identifier '#{b}'" unless @env.assigned?(b)
    entry_a = @env.get_entry(a)
    entry_b = @env.get_entry(b)
    raise "ADD expects INTEGERs" unless entry_a[:type] == :int && entry_b[:type] == :int
    entry_a[:value] = entry_a[:value] + entry_b[:value]
    nil
  end

  # IF identifier line_no
  # If identifier is an empty list OR the number zero, jump to line line_no (1-based).
  # Return the new pc (0-based) if jump, otherwise nil.
  def conditional(id, line_no_str)
    raise "Undefined identifier '#{id}'" unless @env.assigned?(id)
    unless line_no_str =~ /\A\d+\z/
      raise "IF expects positive integer line number, got '#{line_no_str}'"
    end

    line_no = line_no_str.to_i
    new_pc = line_no - 1
    raise "IF jump target out of range: #{line_no}" if new_pc < 0 || new_pc >= @lines.size

    entry = @env.get_entry(id)
    cond = false
    if entry[:type] == :int
      cond = (entry[:value] == 0)
    elsif entry[:type] == :list
      cond = entry[:value].empty?
    else
      cond = false
    end

    cond ? new_pc : nil
  end

  def print_value(name)
    raise "Undefined identifier '#{name}'" unless @env.assigned?(name)
    entry = @env.get_entry(name)
    if entry[:type] == :int
      puts "#{name} = #{entry[:value]}"
    else
      puts "#{name} = #{entry[:value].to_s}"
    end
    nil
  end

  # ---------- Utilities ----------
  def deep_clone_symbol_value(entry)
    # entry is a { type:, value: }
    if entry[:type] == :int
      entry[:value] # integers are immediate
    else
      # list -> deep copy
      entry[:value].deep_copy
    end
  end
end

# ---------------- Run from command line ----------------
if __FILE__ == $0
  unless ARGV[0]
    puts "Usage: ruby ppl_interpreter.rb <program_file>"
    exit 1
  end

  begin
    interp = Interpreter.new(ARGV[0])
    interp.run
  rescue Errno::ENOENT
    puts "File not found: #{ARGV[0]}"
    exit 1
  end
end
