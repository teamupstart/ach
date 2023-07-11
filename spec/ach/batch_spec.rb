# encoding: utf-8
require 'spec_helper'

describe ACH::Batch do
  let(:credit_entry_1) do
    entry = ACH::EntryDetail.new

    entry.transaction_code = ACH::CHECKING_CREDIT
    entry.routing_number = "000000000"
    entry.account_number = "00000000000"
    entry.amount = 10000 # In cents
    entry.individual_id_number = "Employee Name1"
    entry.individual_name = "Employee Name1"
    entry.originating_dfi_identification = '00000000'
    entry
  end

  let(:credit_entry_2) do
    entry = ACH::EntryDetail.new

    entry.transaction_code = ACH::CHECKING_CREDIT
    entry.routing_number = "999999999"
    entry.account_number = "99999999999"
    entry.amount = 200000 # In cents
    entry.individual_id_number = "Employee Name2"
    entry.individual_name = "Employee Name2"
    entry.originating_dfi_identification = '99999999'
    entry
  end

  let(:debit_entry_1) do
    entry = credit_entry_1.dup
    entry.transaction_code = ACH::CHECKING_DEBIT
    entry
  end

  let(:debit_entry_2) do
    entry = credit_entry_2.dup
    entry.transaction_code = ACH::CHECKING_DEBIT
    entry
  end

  def new_batch
    batch = ACH::Batch.new
    bh = batch.header
    bh.company_name = "Company Name"
    bh.company_identification = "123456789"
    bh.standard_entry_class_code = 'PPD'
    bh.company_entry_description = "DESCRIPTION"
    bh.company_descriptive_date = Date.today
    bh.effective_entry_date = (Date.today + 1)
    bh.originating_dfi_identification = "00000000"
    batch
  end

  describe '#to_ach' do
    it 'should determine BatchHeader#service_class_code if not set' do
      debits = new_batch
      debits.entries << debit_entry_1 << debit_entry_2
      expect(debits.header.service_class_code).to be_nil
      debits.to_ach
      expect(debits.header.service_class_code).to eq(225)

      credits = new_batch
      credits.entries << credit_entry_1 << credit_entry_2
      expect(credits.header.service_class_code).to be_nil
      credits.to_ach
      expect(credits.header.service_class_code).to eq(220)

      both = new_batch
      both.entries << credit_entry_1 << debit_entry_2
      expect(both.header.service_class_code).to be_nil
      both.to_ach
      expect(both.header.service_class_code).to eq(200)
    end

    it 'should not override BatchHeader#service_class_code if already set' do
      debits = new_batch
      debits.header.service_class_code = 200
      debits.entries << debit_entry_1 << debit_entry_2
      debits.to_ach
      expect(debits.header.service_class_code).to eq(200)

      debits = new_batch
      debits.header.service_class_code = '220'
      debits.entries << credit_entry_1 << credit_entry_2
      debits.to_ach
      expect(debits.header.service_class_code).to eq('220')
    end

    it 'should set BatchControl#service_class_code from BatchHeader if not set' do
      batch = new_batch
      batch.header.service_class_code = 200
      expect(batch.control.service_class_code).to be_nil
      batch.to_ach
      expect(batch.control.service_class_code).to eq(200)

      batch = new_batch
      batch.header.service_class_code = '225'
      expect(batch.control.service_class_code).to be_nil
      batch.to_ach
      expect(batch.control.service_class_code).to eq('225')

      debits = new_batch
      debits.entries << debit_entry_1 << debit_entry_2
      expect(debits.header.service_class_code).to be_nil
      expect(debits.control.service_class_code).to be_nil
      debits.to_ach
      expect(debits.header.service_class_code).to eq(225)
    end

    it 'should set BatchControl#company_identification from BatchHeader' do
      batch = new_batch
      expect(batch.control.company_identification).to be_nil
      batch.to_ach
      expect(batch.control.company_identification).to eq("123456789")
    end

    it 'should set BatchControl#originating_dfi_identification from BatchHeader' do
      batch = new_batch
      expect(batch.control.originating_dfi_identification).to be_nil
      batch.to_ach
      expect(batch.control.originating_dfi_identification).to eq("00000000")
    end

    it 'should not override BatchHeader#service_class_code if already set' do
      # Granted that I can't imagine this every being used...
      batch = new_batch
      batch.header.service_class_code = 220
      batch.control.service_class_code = 200
      batch.to_ach
      expect(batch.control.service_class_code).to eq(200)
    end

    context 'when addendum are present' do
      let(:addendum_entry_1) do
        addendum = ACH::Records::Addendum.new
        addendum.entry_detail_sequence_number = credit_entry_1.trace_number
        addendum
      end

      let(:addendum_entry_2) do
        addendum = ACH::Records::Addendum.new
        addendum.entry_detail_sequence_number = credit_entry_2.trace_number
        addendum
      end

      context 'when addendum are nested in the batch' do
        let(:batch) do
          batch = new_batch
          batch.entries << credit_entry_1 << credit_entry_2
          batch.entries << debit_entry_1 << debit_entry_2
          batch.addendas << addendum_entry_1 << addendum_entry_2
          batch
        end

        it 'calculates the batch control correctly' do
          batch.to_ach
          expect(batch.control.entry_count).to eq(6)
          expect(batch.control.credit_total).to eq(credit_entry_1.amount + credit_entry_2.amount)
          expect(batch.control.debit_total).to eq(debit_entry_1.amount + debit_entry_2.amount)
        end
      end

      context 'when addendum are nested in the entry' do
        let(:batch) do
          batch = new_batch
          batch.entries << credit_entry_1 << credit_entry_2
          batch.entries << debit_entry_1 << debit_entry_2
          batch
        end

        before do
          credit_entry_1.addenda << addendum_entry_1
          credit_entry_2.addenda << addendum_entry_2
        end

        it 'calculates the batch control correctly' do
          batch.to_ach
          expect(batch.control.entry_count).to eq(6)
          expect(batch.control.credit_total).to eq(credit_entry_1.amount + credit_entry_2.amount)
          expect(batch.control.debit_total).to eq(debit_entry_1.amount + debit_entry_2.amount)
        end
      end
    end
  end
end
