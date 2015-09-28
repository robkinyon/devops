require 'aws-sdk'
describe DevOps::DNS do
  let(:client) { instance_double('Aws::Route53::Client') }
  let(:dns) { DevOps::DNS.new(client) }

  describe '#zones' do
    it "can load no zones" do
      expect(client).to receive(:list_hosted_zones).and_return(
        Aws::Route53::Types::ListHostedZonesResponse.new(
          hosted_zones: [],
          is_truncated: false,
        )
      )
      expect(dns.zones).to eq({})
      expect(dns.zone_for('foo.test')).to eq(nil)
    end

    it "can load one zone" do
      expect(client).to receive(:list_hosted_zones).and_return(
        Aws::Route53::Types::ListHostedZonesResponse.new(
          hosted_zones: [
            Aws::Route53::Types::HostedZone.new(
              id: 'id for foo.test.',
              name: 'foo.test.',
            ),
          ],
          is_truncated: false,
        )
      )
      expect(dns.zones.keys).to eq(['foo.test.'])
      expect(dns.zone_for('foo.test')).to be_an(DevOps::DNS::Zone)
      expect(dns.zone_for('foo.test')).to eq(dns.zone_for('foo.test.'))
    end

    # NOTE: There is an open question on SO about this:
    # http://stackoverflow.com/q/32830911/1732954
    it "can handle pagination (one level)" do
      expect(client).to receive(:list_hosted_zones).
        and_return(
          Aws::Route53::Types::ListHostedZonesResponse.new(
            hosted_zones: [
              Aws::Route53::Types::HostedZone.new(
                id: 'id for foo.test.',
                name: 'foo.test.',
              ),
            ],
            is_truncated: true,
            marker: 'marker',
          ),
      #    )
      #  )
      #expect(client).to receive(:list_hosted_zones).
      #  with(next_marker: 'marker').
      #  and_return(
          Aws::Route53::Types::ListHostedZonesResponse.new(
            hosted_zones: [
              Aws::Route53::Types::HostedZone.new(
                id: 'id for bar.test.',
                name: 'bar.test.',
              ),
            ],
            is_truncated: false,
          )
        )

      expect(dns.zones.keys).to eq(['foo.test.', 'bar.test.'])
      expect(dns.zone_for('foo.test')).to be_an(DevOps::DNS::Zone)
      expect(dns.zone_for('foo.test')).to eq(dns.zone_for('foo.test.'))
    end

    it "can handle pagination (two levels)" do
      expect(client).to receive(:list_hosted_zones).
        and_return(
          Aws::Route53::Types::ListHostedZonesResponse.new(
            hosted_zones: [
              Aws::Route53::Types::HostedZone.new(
                id: 'id for foo.test.',
                name: 'foo.test.',
              ),
            ],
            is_truncated: true,
            marker: 'marker',
          ),
      #    )
      #  )
      #expect(client).to receive(:list_hosted_zones).
      #  with(next_marker: 'marker').
      #  and_return(
          Aws::Route53::Types::ListHostedZonesResponse.new(
            hosted_zones: [
              Aws::Route53::Types::HostedZone.new(
                id: 'id for bar.test.',
                name: 'bar.test.',
              ),
            ],
            is_truncated: true,
            marker: 'marker2',
          ),
          Aws::Route53::Types::ListHostedZonesResponse.new(
            hosted_zones: [
              Aws::Route53::Types::HostedZone.new(
                id: 'id for baz.test.',
                name: 'baz.test.',
              ),
            ],
            is_truncated: false,
          )
        )

      expect(dns.zones.keys).to eq(['foo.test.', 'bar.test.', 'baz.test.'])
      expect(dns.zone_for('foo.test')).to be_an(DevOps::DNS::Zone)
      expect(dns.zone_for('foo.test')).to eq(dns.zone_for('foo.test.'))
    end

    it 'handles errors thrown' do
      expect(client).to receive(:list_hosted_zones).
        and_raise(Aws::Route53::Errors::ServiceError.new(:context, 'message'))

      expect{ dns.zones }.to raise_error(DevOps::Error)
    end
  end

  describe '#ensure_zone' do
    it 'can create a zone' do
      expect(client).to receive(:list_hosted_zones).
        and_return(
          Aws::Route53::Types::ListHostedZonesResponse.new(
            hosted_zones: [],
            is_truncated: false,
          ),
          Aws::Route53::Types::ListHostedZonesResponse.new(
            hosted_zones: [
              Aws::Route53::Types::HostedZone.new(
                id: 'id for foo.test.',
                name: 'foo.test.',
              ),
            ],
            is_truncated: false,
          )
        )
      expect(client).to receive(:create_hosted_zone).
        with(name: 'foo.test', caller_reference: "Creating zone foo.test")

      expect(dns.zone_for('foo.test')).to eq(nil)

      expect(dns.ensure_zone('foo.test')).to be_an(DevOps::DNS::Zone)

      # Ensure we can call it again without invoking the client
      expect(dns.ensure_zone('foo.test')).to eq(dns.zone_for('foo.test'))
    end

    it 'handles errors thrown' do
      expect(client).to receive(:list_hosted_zones).
        and_return(
          Aws::Route53::Types::ListHostedZonesResponse.new(
            hosted_zones: [],
            is_truncated: false,
          )
        )
      expect(client).to receive(:create_hosted_zone).
        with(name: 'foo.test', caller_reference: "Creating zone foo.test").
        and_raise(Aws::Route53::Errors::ServiceError.new(:context, 'message'))

      expect{ dns.ensure_zone('foo.test') }.to raise_error(DevOps::Error)
    end
  end
end
