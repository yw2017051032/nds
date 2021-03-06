# Will call request response bulk, delta, and by transaction ID

require 'rubygems'
require 'pry'
gem 'nokogiri' 
require 'nokogiri' 
require 'fileutils'
require 'pony'

Pony.options = {
  :subject => "Some Subject",
  :body => "This is the body.",
  :via => :smtp,
  :to => ['scott.weaver@jma-solutions.com', 'scott12@fastmail.fm'],
  :from => 'scott.weaver@jma-solutions.com',
  :via_options => {
    :address              => 'mail.messagingengine.com',
    :port                 => '587',
    :enable_starttls_auto => true,
    :user_name            => '',   # need to add back in
    :password             => '',   # need to add back in
    :authentication       => :plain, # :plain, :login, :cram_md5, no auth by default
    :domain               => "localhost.localdomain"
  }
}

class Notam
  attr_reader :notam_doc, :trans_id, :scenario, :xsi_nil_present, :begin_position, :end_position, :time_position

  def initialize(notam_doc)
    @notam_doc = notam_doc   # this will be a Nokogiri node (or a Nokogiri document with pointer to node) need to search relative from here
    @trans_id = self.notam_doc.attr('id')
    @scenario = self.notam_doc.xpath(".//scenario/text()")
    @begin_position = self.notam_doc.xpath(".//beginPosition/text()")
    @end_position = self.notam_doc.xpath(".//endPosition/text()")
    @time_position = self.notam_doc.xpath(".//timePosition/text()")
    xsi_nil_list = self.notam_doc.xpath(".//*[@nil='true'][text()]")
    @xsi_nil_present = xsi_nil_list.size > 0
    #    @fns_id_array = notams.collect { |notam| notam.attr('id') }
  end
end

class RequestResponse   # Will create the appropriate request.xml file for the curl command and capture the output in response.xml
  attr_reader :endpoint, :username, :password, :request_type, :trans_id, :delta_date, :request_xml, :response, :pretty_response, :delta_file_name, :delta_file_name_pretty, :fns_id_array, :scenario_ids, :notam_array

  def initialize(params = {})    #endpoint, username, password, request_type
    @username     = params.fetch(:username, '')
    @password     = params.fetch(:password, '')
    @endpoint     = params.fetch(:endpoint, '')
    @request_type = params.fetch(:request_type, '')    # only one to have a default
    @trans_id     = params.fetch(:trans_id, '')        # this should be in NOTAM only and not here
    @delta_date   = params.fetch(:delta_date, '')
  end

  def xml_request_template
'<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:wfs="http://www.opengis.net/wfs/2.0" xmlns:fes="http://www.opengis.net/fes/2.0">
   <soapenv:Header xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
      <wsse:Security>
         <wsse:UsernameToken>
             <wsse:Username>USERNAME</wsse:Username>
            <wsse:Password>PASSWORD</wsse:Password>
         </wsse:UsernameToken>
      </wsse:Security>
   </soapenv:Header>
   <soapenv:Body>
      <wfs:GetFeature service="WFS" version="2.0.0" resultType="results" outputFormat="application/aixm+xml; version=5.1">
         <wfs:Query typeNames="">
            <fes:Filter>
               REQUEST
            </fes:Filter>
         </wfs:Query>
      </wfs:GetFeature>
   </soapenv:Body>
</soapenv:Envelope>'
  end
  
  def create_request_xml_file(path)
    xrt1 = xml_request_template.sub "USERNAME",  @username
    xrt2 = xrt1.sub "PASSWORD", @password

    case self.request_type
    when :by_trans_id
      @request_xml = xrt2.sub "REQUEST",  "<fes:ResourceId rid=\"#{trans_id.to_s}\"/>"
    when :delta
      @request_xml = xrt2.sub "REQUEST",  "<fes:Function name=\"SearchByLastUpdateDate\"><fes:Literal>#{delta_date.to_s}</fes:Literal></fes:Function>"
    when :bulk
    else
      puts "Request must be of type :bulk, :delta, or :transaction_id"
    end
    File.open(path, 'w') { |rf| rf.puts request_xml}  # make the file xml_request
    ''
  end
  
  def create_response_file(path)
    @delta_file_name        = "files_delta/delta_#{self.delta_date}.xml"
    @delta_file_name_pretty = "files_delta_pretty/delta_#{self.delta_date}_pretty.xml"
    curl_command_1 = 'curl --silent --insecure -H "Content-Type: text/xml; charset=utf-8" -H "SOAPAction:"  -d @'+path+' -X POST END_POINT > '+@delta_file_name
    curl_command = curl_command_1.sub("END_POINT",self.endpoint)
    system(curl_command)
  end

  def create_pretty_response_file
    @response = File.read(self.delta_file_name)
    puts @response[0..5000]
    pretty_response = Nokogiri::XML(@response) { |config| config.strict }
    @pretty_response = pretty_response
    File.open(@delta_file_name_pretty+"_pretty.xml", 'w') { |rf| rf.puts pretty_response}
    doc = pretty_response.remove_namespaces!   # seems to be necessary for Nokogiri - simplifies XPATH statements too
    notam_docs = doc.xpath("//AIXMBasicMessage")
    @notam_array = notam_docs.collect do |notam|
      Notam.new(notam)
    end
  end

  def inspect_notams
    puts "notam_array.size #{notam_array.size}"
    notam_array.collect do |nd|
      puts "transaction ID: #{nd.trans_id}, scenario: #{nd.scenario}, xsi_nil_issue?: #{nd.xsi_nil_present}, endPoistion: #{nd.begin_position}"
    end      
  end

end

def find_time_over_ten_minutes_ago_as_string
  hours_ago = 2   # start at 10 hours ago
  time_range = hours_ago * 60 * 60 # convert hours to seconds
  t = Time.now - time_range
  t.strftime "%Y-%m-%dT%H:%M:%S"
end

#transaction_id = "47780365" # for .81
#transaction_id = "" # for .75
transaction_id = "" # for 2nd floor test
request_type  = :delta
delta_date = "2018-04-13T16:00:00"
#delta_date = "2018-04-13T08:00:00"
#delta_date = "2018-04-12T08:00:00"

delta_date = find_time_over_ten_minutes_ago_as_string

path = "temporary/request.xml"
system_information_hash = File.read("ignore/connection_information.rb")
system_information = eval(system_information_hash)
username = system_information[:username]
password = system_information[:password]
endpoint = system_information[:endpoint]

req = RequestResponse.new(:endpoint => endpoint, :username => username, :password => password, :request_type => request_type, :trans_id => transaction_id, :delta_date => delta_date)
req.create_request_xml_file(path)
req.create_response_file(path)
req.create_pretty_response_file
req.inspect_notams
puts delta_date
exit
#req.extract_fns_id_array
#req.determine_if_xsi_nil
#req.process_all_notams
##################################
##################################
#
#  Unused Below
#
##################################
##################################
class ValidationError
    
  attr_reader :xmlfilename, :scenario, :href_array_string, :good_hrefs, :valid_hrefs, :an_offender
  
  def initialize(xmlfilename)
    # Instance variables  
    @xmlfilename = xmlfilename
    read_lines = IO.readlines(xmlfilename)
    xml_file_string = read_lines.join('')

    @scenario = 'none'
    scenario_split = xml_file_string.split("<event:scenario>")
    yy = scenario_split[1] unless scenario_split.nil?
    @scenario = yy[0..10].split("<")[0] unless yy.nil?

    href_split = xml_file_string.split("href=\"")[1..-1]
    href_split.shift # only interested in what is after the first href (remove all before it)
    href_array = []
    href_split.map do |st|
      href_array << st.split("\"")[0]
    end
    @good_hrefs = true
    href_array.map do |hr|
      @good_hrefs = false if hr[0] != '#'
    end
    @href_array_string = href_array.join(", ")

    @valid_hrefs = true
    @an_offender = false
    href_array.map do |hr|
      hr_temp = hr
      hr_temp = hr[1..-1] if hr[0] == "#"  #hr_temp is hr, shaved of # if necessary
      if not hr_temp.nil? and not xml_file_string.include?(['"',hr_temp,'"'].join)
        @valid_hrefs = false
        @an_offender = hr_temp
      end
    end
  end
end  

def load_a_notam(ti)
  xml_request_1 = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:wfs="http://www.opengis.net/wfs/2.0" xmlns:fes="http://www.opengis.net/fes/2.0">
   <soapenv:Header xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
      <wsse:Security>
         <wsse:UsernameToken>
             <wsse:Username>UAT_NDS_USER_01</wsse:Username>
            <wsse:Password>Password123!</wsse:Password>
         </wsse:UsernameToken>
      </wsse:Security>
   </soapenv:Header>
   <soapenv:Body>
      <wfs:GetFeature service="WFS" version="2.0.0" resultType="results" outputFormat="application/aixm+xml; version=5.1">
         <wfs:Query typeNames="">
            <fes:Filter>
               <fes:ResourceId rid="'
  xml_request_2 = '"/>
            </fes:Filter>
         </wfs:Query>
      </wfs:GetFeature>
   </soapenv:Body>
</soapenv:Envelope>'
  xml_request = xml_request_1 + ti.to_s + xml_request_2
  File.open("request_xml.xml", 'w') { |rf| rf.puts xml_request }  # make the file xml_request
  connection_information = File.read("../ignore/connection_information.rb")
  curl_command_for_trans_id = 'curl --silent --insecure -H "Content-Type: text/xml; charset=utf-8" -H "SOAPAction:"  -d @request_xml.xml -X POST  https://155.178.63.81/notamWFS/services/NOTAMDistributionService > files_transaction_id/'+ti.to_s+'.xml'
  system(curl_command_for_trans_id)                               # have ruby run the req/resp service 
end

def load_all_notams(transaction_array)  
  transaction_array.collect do |trans_id|
    load_a_notam(trans_id)
  end
end


def get_bad_xsi(xml_file)
  nil_splitter = 'xsi:nil="true">'                  # if this is an end tag
  xsi_array = xml_file.split(nil_splitter)
  if (xsi_array.size > 1)
   xsi_array.collect do |xsi_piece|
#      puts xsi_piece.split('>')[-1] + nil_splitter
    end
  end
  xsi_array.size
end

def get_scenario(xml_file)
  scenario_splitter = 'scenario'  
  xml_file.split(scenario_splitter)[1].split('>')[1].split('<')[0]
end

def parse_invalid_file(xml_file_name, xml_file, trans_id,e)
#  puts "Caught exception: #{xml_file_name} #{e}"
  xsi_array_size = get_bad_xsi(xml_file)
  scenario = get_scenario(xml_file)
  puts "Invalid XML:  Transactionid: " + trans_id.to_s + "   Scenario: " + scenario + "    Number of xsi issues: " + xsi_array_size.to_s
end

def analyze(transaction_array,i)
  issue_present_for_batch = false
  sample_bad_doc = "Initial bad doc (not a true error)"
  transaction_array.collect do |trans_id|
    xml_file_name = "files_transaction_id/#{trans_id}.xml"   
    xml_file = File.read(xml_file_name)
    begin
      doc     = Nokogiri::XML(xml_file) { |config| config.strict }
      issue_present = parse_valid_file(doc, trans_id,i)
      if issue_present
        issue_present_for_batch = issue_present
        sample_bad_doc = doc
      end
    rescue Nokogiri::XML::SyntaxError => e
      puts "bad file #{trans_id}"
#      parse_invalid_file(xml_file_name, xml_file,trans_id,e)
    end
  end
  return [issue_present_for_batch, sample_bad_doc]
end

transaction_id_array = [47780365,47780366,47780367]

transaction_id_array_w_one = transaction_id_array + [1]

num = 200000
i = 0
old_issue_present = false
issue_present_for_batch = false
while i < num  do
  puts i
  load_all_notams(transaction_id_array)
  issue_present_for_batch, sample_bad_doc = analyze(transaction_id_array_w_one,i)
  puts "Email Sent: Issue Present for Batch? #{issue_present_for_batch}" if i==0
  #Pony.mail(:subject => "#{Time.now.to_s} Program starts", :body => "First batch: #{issue_present_for_batch.to_s}") if i==0
  
  if (old_issue_present != issue_present_for_batch)
    if issue_present_for_batch
      puts "Email Sent: Issue Present For Batch"
      # Pony.mail(:subject => "#{Time.now.to_s} Issue Present", :body => "#{sample_bad_doc}")
    else
      puts "Email Sent: Issue Not Present For Batch"
      # Pony.mail(:subject => "#{Time.now.to_s} Issue not Present", :body => "#{sample_bad_doc}")
    end
  end
  
  old_issue_present = issue_present_for_batch
  i +=1
  sleep(60)
end

