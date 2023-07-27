require 'spec_helper'

module ACH
  module Records
    describe EntryDetail do
      subject(:entry_detail) { EntryDetail.new }

      describe '#record_type' do
        it "is a constant field with the value of '6'" do
          expect(subject.record_type_to_ach).to eq('6')
          expect(subject).not_to respond_to(:record_type=)
        end
      end

      describe '#transaction_code' do
        it_behaves_like 'a transaction code (String)'
      end

      describe '#routing_number' do
        it_behaves_like 'a routing number (String)'
      end

      describe '#account_number' do
        it_behaves_like 'an account number (String)'
      end

      describe '#amount' do
        let(:amount_length) { 10 }
        it_behaves_like 'an amount (Integer)'
      end

      describe '#individual_name' do
        it 'should truncate fields that exceed the length in left_justify' do
          entry_detail.individual_name = "Employee Name That Is Much Too Long"
          expect(entry_detail.individual_name_to_ach).to eq("Employee Name That Is ")
        end

        it 'should remove new line characters' do
          entry_detail.individual_name = "Multiline\nName\r\n"
          expect(entry_detail.individual_name_to_ach).to eq("MultilineName         ")
        end

        it 'should strip non ascii characters' do
          entry_detail.individual_name = "Jacob Møller"
          expect(entry_detail.individual_name_to_ach).to eq("Jacob Mller           ")
        end
      end

      describe '#to_ach' do
        before(:each) do
          entry_detail.transaction_code = ACH::CHECKING_CREDIT
          entry_detail.routing_number = '091000019'
          entry_detail.account_number = '123'
          entry_detail.amount = 607105
          entry_detail.individual_id_number = '555121234'
          entry_detail.individual_name = 'Employee Name'
          entry_detail.originating_dfi_identification = '021000021'
          entry_detail.trace_number = 1
        end

        it 'is a string with the formatted fields'
      end
    end
  end
end
