require 'aws-sdk'
describe DevOps::DNS do
  let(:client) { instance_double('Aws::Route53::Client') }
  let(:dns) { DevOps::DNS.new(client) }

  def setup_zone_list(*rv)
    expect(client).to receive(:list_hosted_zones).
      and_return(*rv)
  end

  def setup_paginated_zone_list(with_returns)
    with_returns.each do |with, returns|
      expect(client).to receive(:list_hosted_zones).ordered.
        with(with).
        and_return(*returns)
    end
  end

  def zones(zones=[], overrides={})
    opts = {
      hosted_zones: zones,
      is_truncated: false,
    }.merge(overrides)

    Aws::Route53::Types::ListHostedZonesResponse.new(opts)
  end

  def zone(opts)
    Aws::Route53::Types::HostedZone.new(opts)
  end

  def setup_empty_zone_list
    setup_zone_list( zones() )
  end

  describe '#zones' do
    it "can load zero zones" do
      setup_empty_zone_list()

      expect(dns.zones).to eq({})
      expect(dns.zone_for('foo.test')).to eq(nil)
    end

    it "can load one zone" do
      setup_zone_list(
        zones(
          [ zone(id: 'id for foo.test.', name: 'foo.test.') ],
        )
      )

      expect(dns.zones.keys).to match_array(['foo.test.'])
      expect(dns.zone_for('foo.test')).to be_an(DevOps::DNS::Zone)
      expect(dns.zone_for('foo.test')).to eq(dns.zone_for('foo.test.'))
    end

    # NOTE: There is an open question on SO about this:
    # http://stackoverflow.com/q/32830911/1732954
    it "can handle pagination (one level)" do
      setup_paginated_zone_list(
        no_args => [
          zones(
            [ zone(id: 'id for foo.test.', name: 'foo.test.') ],
            is_truncated: true,
            marker: 'marker',
          ),
        ],
        { marker: 'marker' } => [
          zones(
            [ zone(id: 'id for bar.test.', name: 'bar.test.') ],
          )
        ],
      )

      expect(dns.zones.keys).to match_array(['foo.test.', 'bar.test.'])
      expect(dns.zone_for('foo.test')).to be_an(DevOps::DNS::Zone)
      expect(dns.zone_for('foo.test')).to eq(dns.zone_for('foo.test.'))
    end

    it "can handle pagination (two levels)" do
      setup_paginated_zone_list(
        no_args => [
          zones(
            [ zone(id: 'id for foo.test.', name: 'foo.test.') ],
            is_truncated: true,
            marker: 'marker',
          ),
        ],
        { marker: 'marker' } => [
          zones(
            [ zone(id: 'id for bar.test.', name: 'bar.test.') ],
            is_truncated: true,
            marker: 'marker2',
          )
        ],
        { marker: 'marker2' } => [
          zones(
            [ zone(id: 'id for baz.test.', name: 'baz.test.') ],
          )
        ],
      )

      expect(dns.zones.keys).to match_array(['foo.test.', 'bar.test.', 'baz.test.'])
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
      setup_zone_list(
        zones(),
        zones(
          [ zone(id: 'id for foo.test.', name: 'foo.test.') ],
        ),
      )

      expect(client).to receive(:create_hosted_zone).
        with(name: 'foo.test', caller_reference: "Creating zone foo.test")

      expect(dns.zone_for('foo.test')).to eq(nil)

      expect(dns.ensure_zone('foo.test')).to be_an(DevOps::DNS::Zone)

      # Ensure we can call it again without invoking the client
      expect(dns.ensure_zone('foo.test')).to eq(dns.zone_for('foo.test'))
    end

    it 'handles errors thrown' do
      setup_empty_zone_list()

      expect(client).to receive(:create_hosted_zone).
        with(name: 'foo.test', caller_reference: "Creating zone foo.test").
        and_raise(Aws::Route53::Errors::ServiceError.new(:context, 'message'))

      expect{ dns.ensure_zone('foo.test') }.to raise_error(DevOps::Error)
    end
  end
end
