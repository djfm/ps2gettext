#!/usr/bin/ruby

require 'optparse'
require 'strscan'
require 'find'
require 'writeexcel'
require 'shellwords'

require_relative 'scanner'

module PS2Gettext
	class Converter
		def initialize options
			@options = options
			@ops = []

			@exps = {
				'.php' => {
					/(?:\$\w+->l|Translate::getAdminTranslation)\(#{@str_exp}\)/ => {string: 2}
				},
				'.tpl' => {
					/\{l s=#{@str_exp}.*?\}/ => {string: 2}
				}
			}

			@scan_settings = {
				'.php' => {
					/(\$this->l|Translate::getAdminTranslation|Tools::displayError|\w+::l)\s*\(\s*/ => {
						:type => :php_function_call
					}
				},
				'.tpl' => {
					/\{(l)\s+/ => {
						:type => :smarty_funtion_call
					}
				}
			}
		end

		def whitelisted file
			return false if file=~/\/tools\//
			true
		end

		def convert path
			Find.find path do |file|
				next unless whitelisted file
				# Get path relative to path argument, make sure it starts with a '/'.
				rel_path = (rel_path=file[path.length..-1])[0] == '/' ? rel_path : "/#{rel_path}" 
				begin
					if settings = @scan_settings[ext=File.extname(file)]
						settings.each_pair do |exp, info|
							scanner = StringScanner.new(File.read(file))

							while scanner.scan_until exp
								if info[:type] == :php_function_call
									match = scanner[0]
									construct = scanner[1]

									margs = scanner.scan_arguments
									
									match += margs[0]
									args = margs[1]

									if ws=scanner.scan(/\s+/)
										match += ws
									end
									
									if (c=scanner.getch) == ')'
										match += c
										rewrite({ 
											:file => file,
											:ext => ext,
											:construct => construct,
											:args => args,
											:match => match
										})
									else
										puts "Fail in #{file}:\n#{match}"
										exit
									end
								elsif info[:type] == :smarty_funtion_call 
									match = scanner[0]
									construct = scanner[1]
									marglist = scanner.scan_smarty_arguments
									if marglist
										match += marglist[0]
										if (close=scanner.getch) == '}'
											match += '}'
											args = marglist[1]
											rewrite({ 
												:file => file,
												:ext => ext,
												:construct => construct,
												:args => args,
												:match => match
											})
										else
											puts "Fail in #{file}:\n#{match}"
											exit
										end
									end
								end
							end
						end
					end
				rescue ArgumentError => e
					puts "Problem in file '#{file}': #{e}."
				end
			end

			if @options[:for_real]
				commit
			end
		end

		def guess_domain params
			if params[:construct] == 'Tools::displayError'
				return 'errors'
			elsif params[:construct] == 'Translate::getAdminTranslation'
				return 'admin'
			elsif params[:construct] == 'Mail::l'
				return 'mails'
			end

			if theme=params[:file][/\/themes\/([^\/]+)\//, 1]
				return "theme-#{theme}"
			end

			if params[:file]=~/\/pdf\//
				return 'pdfs'
			end

			if (not params[:file]=~/\/modules/) and params[:file]=~/\/classes\//
				return 'admin'
			end

			if params[:file]=~/\/controllers\/admin\//
				return 'admin'
			end

			if params[:file]=~/\/install-dev\//
				return 'installer'
			end

			if mod=params[:file][/\/modules\/([^\/]+)\//, 1]
				return "module-#{mod}"
			end

			if params[:ext] == '.tpl' and params[:args]['pdf']
				return 'pdfs'
			end

			#root of all themes dir
			if params[:file]=~/\/themes\//
				return 'themes'
			end

			abort "No domain could be inferred from #{params}"

			''
		end

		def valid_call params
			if params[:file]=~/\/controllers\/front\// and params[:construct] == "$this->l"
				return false
			end
			true
		end

		def rewrite params

			params[:construct] = params[:construct].gsub(/\s+/, '')

			if valid_call params
				params.merge!(:domain => guess_domain(params))
				params.merge!(:transformed => transform(params))

				if params[:transformed]
					@ops << params
				end
			end
		end

		def get_string str
			if str.length >= 2 and str[0] == str[-1] and %w(' ").include?(str[0])
				str[1...-1]
			else
				nil
			end
		end

		def transform params
			if params[:args].empty?
				return nil
			end

			if params[:ext] == '.php'

				return nil unless get_string(params[:args][0])
					
				if params[:domain] == 'admin'
					if params[:construct] == '$this->l' or params[:construct] == 'Translate::getAdminTranslation'
						#l($string, $class = null, $addslashes = false, $htmlentities = true)
						#getAdminTranslation($string, $class = 'AdminTab', $addslashes = false, $htmlentities = true, $sprintf = null)
						
						sprintf = nil
						htmlentities = true
						addslashes = false

						if slashes=params[:args][2]
							if %w(true TRUE).include? slashes
								addslashes = true
							elsif %w(false FALSE null).include? slashes
								addslashes = false
							else
								abort "addslashes: <#{slashes}>"
							end
						end

						if entities=params[:args][3]
							if %w(false FALSE).include? entities
								htmlentities = false
							else
								abort "htmlentities: <#{entities}>"
							end
						end

						options = {}
						if addslashes
							options['js'] = 'true'
						end

						if !htmlentities
							options['allow_html'] = 'true'
						end

						if params[:args][3]
							options['sprintf'] = params[:args][3]
						end

						optstr = options.empty? ? '' : (', array('+options.map{|k, v| "'#{k}' => #{v}"}.join(", ")+')')

						return "__(#{params[:args][0]}, '#{params[:domain]}'#{optstr})"
					end
				end

				if params[:construct] == 'Tools::displayError'
					#displayError($string = 'Fatal error', $htmlentities = true, Context $context = null)
					if get_string(params[:args][0])
						
						htmlentities = true
						if entities=params[:args][1]
							if %w(false FALSE).include? entities
								htmlentities = false
							else
								htmlentities = "!#{entities}"
								puts "htmlentities?? <#{entities}>"
							end
						end

						options = {}
						if !htmlentities
							options['allow_html'] = 'true'
						end
						optstr = options.empty? ? '' : (', array('+options.map{|k, v| "'#{k}' => #{v}"}.join(", ")+')')

						if params[:args][2]
							abort "HAHA"
						end

						return "__(#{params[:args][0]}, '#{params[:domain]}'#{optstr})"
					end
				end

				if params[:construct] == 'Mail::l'
					lang = nil
					if params[:args][1] and not %w(NULL null).include?(params[:args][1])
						lang = params[:args][1]
					end
					if !lang and params[:args][2]
						lang = params[:args][2]
					end

					lang = lang ? ", array('language' => #{lang})" : ''
					return "__(#{params[:args][0]}, '#{params[:domain]}'#{lang})"
				end

				if params[:domain] == 'pdfs'
					return "__(#{params[:args][0]}, '#{params[:domain]}')"
				end

				if params[:domain] == 'installer'
					optstr = params[:args].length == 1 ? '' : ", array('sprintf' => array(#{params[:args][1..-1].join(", ")}))"
					return "__(#{params[:args][0]}, '#{params[:domain]}'#{optstr})"
				end

				if params[:domain] =~ /^module\-/
					return "__(#{params[:args][0]}, '#{params[:domain]}')"
				end
			
			elsif params[:ext] == '.tpl'
				if !params[:args]['s'] or !get_string(params[:args]['s'])
					return nil
				end

				escape_html = true
				escape_js = false

				if js=params[:args]['js']
					if js == '1'
						escape_js = true
					elsif js == '0'
					else
						abort "Js: <#{js}>"
					end
				end

				if slashes=params[:args]['slashes']
					if slashes == '1'
						escape_js = true
					else
						abort "Slashes: <#{slashes}>"
					end
				end

				js = escape_js ? ' js=1' : ''

				sprintf = params[:args]['sprintf'] ? " sprintf=#{params[:args]['sprintf']}" : ''

				return "{l s=#{params[:args]['s']}#{sprintf}#{js} d='#{params[:domain]}'}"

			end

			abort "Could not transform call #{params}"
		end

		def dump_excel
			wb = WriteExcel.new "rewrites.xls"
			ws = wb.add_worksheet
			row = 0
			ws.write(row, 0, %w(Ext File Domain Construct Args Match Transformed))
			@ops.each do |op|
				row+=1
				ws.write(row, 0, [
					op[:ext],
					op[:file],
					op[:domain],
					op[:construct],
					op[:args],
					op[:match],
					op[:transformed]
				])
			end
			wb.close
		end

		def sedscape str
			str.gsub('/', '\/').gsub('\\', '\\\\').gsub('&', '\&').shellescape
		end

		def commit
			replacements = Hash.new { |hash, key| hash[key] = Hash.new }

			@ops.each do |op|
				replacements[op[:file]][op[:match]] = op[:transformed]
			end

			replacements.each_pair do |file, replacements|
				puts "Processing #{file}..."
				$debug = (file=="/var/www/psnt/classes/module/Module.php")
				File.write(file, File.read(file).replace_all(replacements))
			end
		end
	end
end

#PS2Gettext::StringScanner.run_tests
#s = PS2Gettext::StringScanner.new "'Unable to open backup file(s).').' \"'.addslashes($backupfile).'\"')"
#puts "#{s.scan_arguments}"
#exit

options = {
	for_real: false
}

opts = OptionParser.new do |opts|
	opts.banner = "Usage: ps2gettext.rb [options] prestashop_directory"

	opts.on '-f', '--for-real', 'Really change the code, this is dangerous, but a necassary evil.' do
		options[:for_real] = true
	end

	opts.on_tail '-h', '--help', 'Show this message' do
		puts opts
		exit
	end
end

begin
	opts.parse!
rescue OptionParser::InvalidOption => e
	puts "Error: #{e}."
	puts opts
	exit
end

if ARGV.length == 0 
	puts "Error: missing prestashop_directory argument."
	puts opts
	exit
elsif ARGV.length > 1
	puts "Error: too many arguments."
	puts opts
	exit
elsif not File.directory?(ARGV[0])
	puts "Error: '#{ARGV[0]}' is not a directory."
	puts opts
	exit
end

converter = PS2Gettext::Converter.new options

converter.convert ARGV[0]
converter.dump_excel