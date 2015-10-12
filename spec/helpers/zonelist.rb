module ZoneList
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

  def zone_for(opts)
    Aws::Route53::Types::HostedZone.new(opts)
  end

  def setup_empty_zone_list
    setup_zone_list( zones() )
  end
end
