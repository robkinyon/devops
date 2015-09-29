require 'devops/error'

require 'devops/dns'

gem 'aws-sdk', '~> 2.1'
require 'aws-sdk'

class DevOps
  def initialize(region='us-east-1')
    Aws.config.update({
      region: region,
      credentials: Aws::SharedCredentials.new,
    })
  end

  def dns
    @dns ||= DevOps::DNS.new
  end
end
