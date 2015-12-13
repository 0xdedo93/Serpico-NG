require 'rubygems'
require 'nokogiri'
require 'zipruby'
require './model/master'

# For now, we need this to clean up import text a bit
def clean(text)
    return unless text

    text = text.gsub(/\s+/, " ")
    text = text.gsub("<br>", "\n")
    text = text.gsub("<p>", "\n")
    text = text.gsub("<description>","")
    text = text.gsub("</description>","")
    text = text.gsub("<solution>","")
    text = text.gsub("</solution>","")

    # burp stores html and needs to be removed, TODO better way to handle this
    text = text.gsub("</p>", "")
    text = text.gsub("<li>", "\n")
    text = text.gsub("</li>", "")
    text = text.gsub("<ul>", "\n")
    text = text.gsub("</ul>", "")
    text = text.gsub("<table>", "")
    text = text.gsub("</table>", "")
    text = text.gsub("<td>", "\n")
    text = text.gsub("</td>", "")
    text = text.gsub("<tr>", "")
    text = text.gsub("</tr>", "")
    text = text.gsub("<b>", "[~~")
    text = text.gsub("</b>", "~~]")
    text = text.gsub("<![CDATA[","")
    text = text.gsub("]]>","")
    text = text.gsub("\n\n","\n")

    text = text.gsub("\n","<paragraph>")

    p text

    return text
end

def parse_nessus_xml(xml)
    vulns = Hash.new
    findings = Array.new
    items = Array.new

    doc = Nokogiri::XML(xml)

    doc.css("//ReportHost").each do |hostnode|
        if (hostnode["name"] != nil)
            host = hostnode["name"]
        end
        hostnode.css("ReportItem").each do |itemnode|
            if (itemnode["port"] != "0" && itemnode["severity"] > "1")

                # create a temporary finding object
                finding = Findings.new()
                finding.title = itemnode['pluginName'].to_s()
                finding.overview = clean(itemnode.css("description").to_s)
                finding.remediation = clean(itemnode.css("solution").to_s)

                # hardcode the risk, the user should fix this
                finding.risk = 0
                finding.damage = 0
                finding.reproducability = 0
                finding.exploitability = 0
                finding.affected_users = 0
                finding.discoverability = 0
                finding.dread_total = 0

                findings << finding

                items << itemnode['pluginID'].to_s()
            end
        end
        vulns[host] = items
        items = []
    end

    vulns["findings"] = findings.uniq
    return vulns
end

def parse_burp_xml(xml)
    vulns = Hash.new
    findings = Array.new
    vulns["findings"] = []

    doc = Nokogiri::XML(xml)
    doc.css('//issues/issue').each do |issue|
        if issue.css('severity').text
            # create a temporary finding object
            finding = Findings.new()
            finding.title = clean(issue.css('name').text.to_s())
            finding.overview = clean(issue.css('issueBackground').text.to_s()+issue.css('issueDetail').text.to_s())
            finding.remediation = clean(issue.css('remediationBackground').text.to_s())

            # hardcode the risk, the user assign the risk
            finding.risk = 0
            finding.damage = 0
            finding.reproducability = 0
            finding.exploitability = 0
            finding.affected_users = 0
            finding.discoverability = 0
            finding.dread_total = 0

            findings << finding

            host = issue.css('host').text
            ip = issue.css('host').attr('ip')
            id = issue.css('type').text
            hostname = "#{ip} #{host}"

            finding.affected_hosts = "#{host} (#{ip})"

            if vulns[hostname]
                vulns[hostname] << id
            else
                vulns[hostname] = []
                vulns[hostname] << id
            end
        end
    end

    # this gets a uniq on the findings and groups hosts, could be more efficient
    findings.each do |single|
        # check if the finding has been added before
        exists = vulns["findings"].detect {|f| f["title"] == single.title }

        if exists
            #get the index
            i = vulns["findings"].index(exists)
            exists.affected_hosts = clean(exists.affected_hosts+"<br>#{single.affected_hosts}")
            vulns["findings"][i] = exists
        else
            vulns["findings"] << single
        end
    end
    return vulns
end
