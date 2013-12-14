#!/usr/bin/ruby

require 'optparse'
require 'strscan'
require 'find'
require 'writeexcel'

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
			true
		end

		def convert path
			Find.find path do |file|
				continue unless whitelisted file
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

									c = scanner.getch
									if c == ')'
										match += c
										if sc=scanner.scan(/\s+;/)
											match += sc
										end
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

			if params[:file]=~/\/pdf\//
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
			if valid_call params
				params.merge!(:domain => guess_domain(params))
				params.merge!(:transformed => transform(params))
				@ops << params
			end
		end

		def transform params

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