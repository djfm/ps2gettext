require 'strscan'

module PS2Gettext
	class StringScanner < ::StringScanner
		def scan_arguments
			start_pos = pos

			state = :default
			quote = :nil
			n_popened = 0

			buffer = ''
			match  = ''
			args = []


			states = [:default]

			store_arg = lambda do
				args << buffer.strip
				buffer = ''
			end

			push_state = lambda do |st|
				if st != state
					states << st
					state = st
				end
			end

			pop_state = lambda do 
				states.pop
				state = states[-1]
			end

			while '' != c=peek(1)
				if state == :default and c == ')'
					break
				end
				c = getch
				match += c

				if state == :default
					#start of string
					if %w(' ").include? c
						push_state.call :string
						quote = c
						buffer += c
					elsif ',' == c
						store_arg.call
					elsif '(' == c
						n_popened += 1
						push_state.call :paren
						buffer += c
					else
						buffer += c
					end
				elsif state == :string
					buffer += c
					if quote == c
						quote = nil
						pop_state.call
					elsif '\\' == c
						push_state.call :escape
					end
				elsif state == :escape
					buffer += c
					pop_state.call
				elsif state == :paren
					buffer += c
					if '(' == c
						n_popened += 1
					elsif ')' == c
						n_popened -= 1
						if 0 == n_popened
							pop_state.call
						elsif n_popened < 0
							return nil
						end
					elsif %w(' ").include? c
						push_state.call :string
						quote = c
					end				
				end
			end

			store_arg.call if buffer.length > 0

			[match, args]

		end

		def scan_until_not_in_string chars
			chars = [chars] unless chars.is_a? Array
			state = :default
			match = ''
			while '' != c=peek(1)
				if state == :default and chars.include? c
					break
				end
				c = getch
				match += c
				if state == :default
					if %w(' ").include? c
						quote = c
						state = :string
					end
				elsif state == :string
					if '\\' == c
						state = :escape
					elsif c == quote
						state = :default
					end
				elsif state == :escape
					state = :string
				end
			end

			match
		end 

		def scan_smarty_arguments
			match = ''
			args = {}

			state = :default
			while '' != c=peek(1)
				if state == :default and c == '}'
					break
				end

				#scan argument name
				if argname=scan(/\w+/)
					match += argname
					if ws=scan(/\s+/)
						match += ws
					end
					if getch == '='
						match += '='
						if ws=scan(/\s+/)
							match += ws
						end
						if peek(1) == '['
							value = scan_until_not_in_string ']'
							if getch == ']'
								value += ']'
								match += value
								args[argname] = value.strip
							else
								return nil
							end
						else
							value = scan_until_not_in_string [' ', '}']
							match += value
							args[argname] = value.strip
						end
						if ws=scan(/\s+/)
							match += ws
						end
					else
						return nil
					end
				else
					return nil
				end
			end

			[match, args]
		end

	end
end