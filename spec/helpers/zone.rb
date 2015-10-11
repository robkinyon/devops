module Zone
  def setup_zone(*rv)
    expect(client).to receive(:list_resource_record_sets).
      with(hosted_zone_id: zone_id).
      and_return(*rv)
  end

  def setup_paginated_zone(with_returns)
    with_returns.each do |with, returns|
      expect(client).to receive(:list_resource_record_sets).ordered.
        with(with.merge(hosted_zone_id: zone_id)).
        and_return(*returns)
    end
  end

  def records(records=[], overrides={})
    opts = {
      resource_record_sets: records,
      is_truncated: false,
    }.merge(overrides)

    Aws::Route53::Types::ListResourceRecordSetsResponse.new(opts)
  end

  def record(opts={})
    Aws::Route53::Types::ResourceRecordSet.new(opts)
  end

  def setup_empty_zone
    setup_zone( records() )
  end

  def expect_change_record(opts)
    if opts[:changes]
      changes = opts[:changes]
    else
      records = opts.has_key?(:values) ?
        opts[:values].map{|e| { value: e }} :
        [{ value: opts[:value] }]

      changes = [
        {
          action: opts[:action] || 'CREATE',
          resource_record_set: {
            name: opts[:name],
            type: opts[:type],
            ttl: record[:ttl] || 600,
            resource_records: records,
          },
        },
      ]
    end

    expect(client).to receive(:change_resource_record_sets).
      with(
        hosted_zone_id: zone_id,
        change_batch: { changes: changes },
      )
  end

  def expect_alias_record(opts)
    expect(client).to receive(:change_resource_record_sets).
      with(
        hosted_zone_id: zone_id,
        change_batch: {
          changes: [
            {
              action: opts[:action] || 'CREATE',
              resource_record_set: {
                name: opts[:name],
                type: opts[:type],
                alias_target: {
                  hosted_zone_id: zone_id,
                  dns_name: opts[:value],
                  evaluate_target_health: false,
                },
              },
            },
          ],
        },
      )
  end
end
