require 'devops/dns/zone'
require 'devops/error'

class DevOps
  class DNS
    attr_reader :client
    def initialize(client=nil)
      @client = client || Aws::Route53::Client.new
    end

    def zones
      load_zones unless @zones
      @zones
    end

    def zone_for(name)
      zones[canonical(name)]
    end

    def ensure_zone(name)
      unless zone_for(name)
        begin
          rv = client.create_hosted_zone(
            name: name,
            caller_reference: "Creating zone #{name}",
          )
        rescue Aws::Route53::Errors::ServiceError => e
          #puts e
          raise DevOps::Error
        end

        refresh_zones
      end
      return zone_for(name)
    end

    private
    def canonical(name)
      name[-1] == '.' ? name : "#{name}."
    end

    def load_zones
      zones = []

      begin
        rv = client.list_hosted_zones
        zones.concat rv.hosted_zones
        while rv.is_truncated
          rv = client.list_hosted_zones(marker: rv.marker)
          zones.concat rv.hosted_zones
        end
      rescue Aws::Route53::Errors::ServiceError => e
        #puts e
        raise DevOps::Error
      end

      @zones = zones.map {|e|
        [ e.name, DevOps::DNS::Zone.new(client, e)]
      }.to_h
    end
    alias_method :refresh_zones, :load_zones
  end
end
