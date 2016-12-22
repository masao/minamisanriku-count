require "erb"
require "sinatra"
require "sinatra/json"
require "rack"
require "rack/contrib"

require "csv"
require "kconv"
require "date"

class UnknownCode < Exception
end

def callnum_to_category( call_number, ndc )
   code = nil
   ndc = ndc.toutf8 if ndc
   case call_number
   when /^([\d])/
      code = $1.dup
   when /^(k[\d])/i
      code = $1.downcase
   when /^kノリ/i
      code = "k5" # 546.5(電車), 537(自動車)など
   when /^([ア-ン])/
      code = "絵本"
   when /^d/i
      code = "DVD"
   when /^c/i
      code = "CD"
   when /^O(\d)/i
      code = $1.dup
   else
      if not ndc.nil? and not ndc.empty? and ndc =~ /^([\d])/
         code = $1.dup
      else
         raise UnknownCode
      end
   end
   code
end

def options
   format = :cli
   option = :items
   filter = {}
   while ARGV[0] =~ /\A-/
      if ARGV[0] =~ /\A-m/
         option = :manifestations
         ARGV.shift
      elsif ARGV[0] =~ /\A-export/
         format = :export
         ARGV.shift
      elsif ARGV[0] =~ /\A-checkout/
         format = :checkout
         ARGV.shift
      elsif ARGV[0] =~ /\A-from/
         ARGV.shift
         filter[:from] = Date.parse(ARGV.shift)
      elsif ARGV[0] =~ /\A-until/
         ARGV.shift
         filter[:until] = ( Date.parse(ARGV.shift) + 1 )
      else
        break
      end
   end
end

def parse_lines(io, format = :export, option = :items)
  Encoding.default_external = "utf-8"
  csv_options = {
    headers: true,
    return_headers: true,
    write_headers: true,
    col_sep: "\t",
  }
  csv = CSV.new(io, csv_options)
  items = {}
  manifestations = {}
  csv.each do |row|
    #item_id, manifestation_id, call_number, item_identifier, ndc, shelf, = line.chomp.split( /\t/ ) if format == :cli
    #manifestation_id, original_title, creator, publisher, pub_date, price, isbn, issn, item_identifier, call_number, item_price, acquired_at, bookstore, budget_type, circulation_status, shelf, library, = line.chomp.split( /\t/ ) if format == :export
    #created_at, item_identifier, call_number, shelf, carrier_type, original_title, = line.chomp.split( /\t/ ) if format == :checkout
    if row["created_at"]
      created_at = Date.parse(row["created_at"])
      next if filter[:from] and filter[:from] > row["created_at"]
      next if filter[:until] and filter[:until] <= row["created_at"]
    end
    item_id = row["item_id"]
    item_id = row["item_identifier"] unless item_id
    shelf = row["shelf"]
    call_number = NKF.nkf( "-WwZ1", row["call_number"].to_s )
    begin
       code = callnum_to_category( call_number, row["ndc"] )
    rescue UnknownCode
       STDERR.puts row.inspect
       next
    end
    manifestations[ code ] ||= {}
    manifestations[ code ][ shelf.to_s ] ||= []
    manifestations[ code ][ shelf.to_s ] << row["manifestation_id"]
    items[ code ] ||= {}
    items[ code ][ shelf.to_s ] ||= []
    items[ code ][ shelf.to_s ] << item_id
  end
  items

  case option
  when :manifestations
      STDERR.puts "Manifestations:"
      @result = manifestations
   else
      STDERR.puts "Items:"
      @result = items
   end
end

class App < Sinatra::Base
  def initialize
    @baseurl = ENV["baseurl"]
    super
  end
  before do
    if not request.secure? and request.host != "localhost"
      redirect request.url.sub('http', 'https')
    end
  end
  get "/" do
    erb :index
  end
  post "/" do
    if params[:file]
      cont = params[:file][:tempfile]
      parse_lines(open(cont))
    end
    erb :index
  end
end
