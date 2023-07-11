require 'spec_helper'

describe ACH::ACHFile do

  subject(:ach_file) do
    # Create ACH file
    ach = ACH::ACHFile.new

    # File Header
    fh = ach.header
    fh.immediate_destination = '999999999'
    fh.immediate_destination_name = 'BANK NAME'
    fh.immediate_origin = '666666666'
    fh.immediate_origin_name = 'BANK NAME'
    fh.transmission_datetime = Time.new(2020, 11, 3, 16, 27)

    ach
  end

  def add_batch(ach, entry_details = 0, balanced = false)
    batch = ACH::Batch.new
    bh = batch.header
    bh.company_name = 'Company Name'
    bh.company_identification = '123456789'
    bh.standard_entry_class_code = 'PPD'
    bh.company_entry_description = 'DESCRIPTION'
    bh.company_descriptive_date = Date.new(2020, 11, 3)

    bh.effective_entry_date =
      ACH::NextFederalReserveEffectiveDate.new(Date.new(2020, 11, 3)).result
    bh.originating_dfi_identification = '77777777'

    entry_details.times { add_detail(batch) }
    if balanced
      add_balancing_entry_detail(batch)
    end

    ach.batches << batch
  end

  def add_detail(batch)
    ed = ACH::EntryDetail.new
    ed.transaction_code = ACH::CHECKING_CREDIT
    ed.routing_number = '111111111'
    ed.account_number = '22222222222'
    ed.amount = 101 # In cents
    ed.individual_id_number = 'Employee Name'
    ed.individual_name = 'Employee Name'
    ed.originating_dfi_identification = '00000000'
    ed.trace_number = 1
    batch.entries << ed
  end

  def add_balancing_entry_detail(batch)
    balanced = ACH::BalancingEntryDetail.new.tap do |entry|
      entry.transaction_code = ACH::CHECKING_DEBIT
      entry.routing_number = '111111111'
      entry.account_number = '22222222222'
      entry.amount = batch.entries.inject(0){|sum, entry| sum + entry.amount}
      entry.account_description = 'OFFSET'
      entry.origin_routing_number = '33333333'
      entry.trace_number = 1
    end
    batch.entries << balanced
  end

  describe '#to_s' do
    context 'with a balancing entry' do
      before(:each) do
        add_batch(ach_file, 4, true)
        ach_file.to_s
      end

      let(:full_file) do
        [
          '101 999999999 6666666662011031627A094101BANK NAME              BANK NAME                      ',
          '5200COMPANY NAME                        1123456789PPDDESCRIPTIO201103201104   1777777770000001',
          '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
          '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
          '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
          '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
          '62711111111122222222222      0000000404               OFFSET                  0333333330000001',
          '820000000500555555550000000004040000000004041123456789                         777777770000001',
          '9000001000001000000050055555555000000000404000000000404                                       ',
          '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999'
        ]
      end

      it 'sets the header and batch' do
        lines = ach_file.to_s.split(ACH.eol)

        expect(lines[0]).to eq(full_file[0])
        expect(lines[1]).to eq(full_file[1])
      end

      it 'sets the credits and debits to the same amount' do
        expect(ach_file.control.debit_total).to eq(404)
        expect(ach_file.control.credit_total).to eq(404)
      end

      it 'shows the offset line' do
        expect(ach_file.to_s.split("\r\n")[6]).to eq(full_file[6])
      end

      it 'shows the debit and credit on line 7' do
        expect(ach_file.to_s.split("\r\n")[7]).to eq(full_file[7])
      end
    end

    context 'with multiple batches' do
      let(:valid_file) do
        [
            '101 999999999 6666666662011031627A094101BANK NAME              BANK NAME                      ',
            '5200COMPANY NAME                        1123456789PPDDESCRIPTIO201103201104   1777777770000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62711111111122222222222      0000000404               OFFSET                  0333333330000001',
            '820000000500555555550000000004040000000004041123456789                         777777770000001',
            '5220COMPANY NAME                        1123456789PPDDESCRIPTIO201103201104   1777777770000002',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '822000000200222222220000000000000000000002021123456789                         777777770000002',
            '9000002000002000000070077777777000000000404000000000606                                       ',
            '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
            '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
            '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
            '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
            '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
            '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
            '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999'
        ]
      end

      before(:each) do
        add_batch(ach_file, 4, true)
        add_batch(ach_file, 2, false)
        ach_file.to_s
      end

      it 'correctly creates the file' do
        lines = ach_file.to_s.split(ACH.eol)

        expect(lines).to eq(valid_file)
      end
    end

    context 'with addendum nested in the entry' do
      let(:valid_file) do
        [
            '101 999999999 6666666662011031627A094101BANK NAME              BANK NAME                      ',
            '5200COMPANY NAME                        1123456789PPDDESCRIPTIO201103201104   1777777770000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62711111111122222222222      0000000404               OFFSET                  0333333330000001',
            '820000000500555555550000000004040000000004041123456789                         777777770000001',
            '5220COMPANY NAME                        1123456789PPDDESCRIPTIO201103201104   1777777770000002',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           1000000000000001',
            '705ADDENDUM 1                                                                      00010000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           1000000000000001',
            '705ADDENDUM 1                                                                      00010000001',
            '705ADDENDUM 2                                                                      00010000001',
            '822000000500222222220000000000000000000002021123456789                         777777770000002',
            '9000002000002000000100077777777000000000404000000000606                                       ',
            '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
            '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
            '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
            '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999'
        ]
      end

      before(:each) do
        add_batch(ach_file, 4, true)
        add_batch(ach_file, 2, false)
        batch = ach_file.batches.last
        entry_1 = batch.entries.first
        entry_2 = batch.entries.last

        addendum_1 = ACH::Records::Addendum.new
        addendum_1.entry_detail_sequence_number = entry_1.trace_number
        addendum_1.sequence_number = 1
        addendum_1.payment_data = 'Addendum 1'
        addendum_2 = ACH::Records::Addendum.new
        addendum_2.entry_detail_sequence_number = entry_2.trace_number
        addendum_2.sequence_number = 1
        addendum_2.payment_data = 'Addendum 2'

        entry_1.addenda << addendum_1
        entry_2.addenda << addendum_1 << addendum_2
        ach_file.to_s
      end

      it 'correctly creates the file' do
        lines = ach_file.to_s.split(ACH.eol)

        expect(lines).to eq(valid_file)
      end
    end

    context 'batch numbers not set' do
      before(:each) do
        add_batch ach_file, 1
        add_batch ach_file, 1
        add_batch ach_file, 1
      end

      it 'increments batch numbers' do
        lines = ach_file.to_s.split("\r\n")
        expect(lines[1][-1]).to eq('1')
        expect(lines[3][-1]).to eq('1')
        expect(lines[4][-1]).to eq('2')
        expect(lines[6][-1]).to eq('2')
        expect(lines[7][-1]).to eq('3')
        expect(lines[9][-1]).to eq('3')
      end
    end

    describe 'padding with 9s' do
      let(:nines) { '9' * 94 }

      context 'number of records mod 10 is not 0' do
        before(:each) do
          add_batch ach_file, 3 # 7 records total
        end

        it 'pads with 9s' do
          lines = ach_file.to_s.split("\r\n")
          expect(lines.length).to eq(10)

          lines[0..6].each do |line|
            expect(line).to_not eq(nines)
          end

          lines[7..9].each do |line|
            expect(line).to eq(nines)
          end

          add_batch ach_file, 5 # add 7 => 14 records total

          lines = ach_file.to_s.split("\r\n")
          expect(lines.length).to eq(20)

          lines[0..13].each do |line|
            expect(line).to_not eq(nines)
          end

          lines[14..19].each do |line|
            expect(line).to eq(nines)
          end
        end

        context 'has addendum records' do
          it 'accounts for addendum records' do
            addendum = ACH::Addendum.new
            addendum.sequence_number = 1
            addendum.payment_data = 'Data'

            ach_file.batches.first.entries.last.addenda << addendum
            lines = ach_file.to_s.split("\r\n")
            expect(lines.length).to eq(10)

            lines[0..7].each do |line|
              expect(line).to_not eq(nines)
            end

            lines[8..9].each do |line|
              expect(line).to eq(nines)
            end
          end
        end
      end

      context 'number of records mod 10 is 0' do
        before(:each) do
          add_batch ach_file, 6 # 7 records total
        end

        it 'does not pad with 9s' do
          lines = ach_file.to_s.split("\r\n")
          expect(lines.length).to eq(10)

          lines.each do |line|
            expect(line).to_not eq(nines)
          end

          add_batch ach_file, 8 # plus batch header and footer

          lines = ach_file.to_s.split("\r\n")
          expect(lines.length).to eq(20)

          lines.each do |line|
            expect(line).to_not eq(nines)
          end
        end
      end
    end

    describe 'eol param' do
      before(:each) do
        add_batch ach_file, 3
      end

      context 'default' do
        subject(:output) { ach_file.to_s }

        it 'uses CRLF' do
          expect(output.split("\r\n").length).to eq(10)
          expect(output[-2..-1]).to eq("\r\n")
        end
      end

      context 'param given' do
        subject(:output) { ach_file.to_s("\n") }
        it 'uses the param' do
          expect(output.split("\r\n").length).to eq(1)
          expect(output.split("\n").length).to eq(10)
          expect(output[-2..-1]).to_not eq("\r\n")
          expect(output[-1]).to eq("\n")
        end

        context 'has addendum records' do
          it 'accounts for addendum records' do
            addendum = ACH::Addendum.new
            addendum.sequence_number = 1
            addendum.payment_data = 'Data'

            ach_file.batches.first.entries.last.addenda << addendum
            expect(ach_file.to_s("\n").include?("\r")).to be(false)
          end
        end
      end
    end
  end

  describe '#initialize' do
    subject { ACH::ACHFile.new(valid_file) }

    let(:valid_file) do
      [
          '101 999999999 6666666662011031627A094101BANK NAME              BANK NAME                      ',
          '5200COMPANY NAME                        1123456789PPDDESCRIPTIO201103201104   1777777770000001',
          '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
          '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
          '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
          '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
          '62711111111122222222222      0000000404               OFFSET                  0333333330000001',
          '820000000500555555550000000004040000000004041123456789                         777777770000001',
          '5220COMPANY NAME                        1123456789PPDDESCRIPTIO201103201104   1777777770000002',
          '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           1000000000000001',
          '705ADDENDUM 1                                                                      00010000001',
          '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           1000000000000001',
          '705ADDENDUM 2                                                                      00010000001',
          '822000000400222222220000000000000000000002021123456789                         777777770000002',
          '9000002000002000000090077777777000000000404000000000606                                       ',
          '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
          '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
          '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
          '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
          '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
          '' # for the trailing carriage return
      ].join(ACH.eol)
    end

    it 'parses the file correctly' do
      ach_file = subject
      expect(ach_file.to_s).to eq(valid_file)
    end

    it 'uses the EntryDetail class on non-CTX entries' do
      expect(subject.batches.first.entries.first.class).not_to eq(ACH::Records::CtxEntryDetail)
    end

    context 'when the file contains CTX entries' do
      let(:valid_file) do
        [
            '101 999999999 6666666662011031627A094101BANK NAME              BANK NAME                      ',
            '5200COMPANY NAME                        1123456789CTXDESCRIPTIO201103201104   1777777770000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62211111111122222222222      0000000101EMPLOYEE NAME  EMPLOYEE NAME           0000000000000001',
            '62711111111122222222222      0000000404               OFFSET                  0333333330000001',
            '820000000500555555550000000004040000000004041123456789                         777777770000001',
            '9000001000001000000050055555555000000000404000000000404                                       ',
            '9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999'
        ].join(ACH.eol)
      end

      it 'parses using the CTXEntry object' do
        expect(subject.batches.first.entries.first.class).to eq(ACH::Records::CtxEntryDetail)
        expect(ach_file.to_s).to eq(valid_file)
      end
    end
  end
end
