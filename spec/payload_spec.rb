# frozen_string_literal: true

module ExcADG
  class AnyPayload
    include Payload
  end

  class WithArgsSanitizer < AnyPayload
    def sanitize _args
      :some
    end
  end

  class CorrectPayload < WithArgsSanitizer
    def get
      -> { :some }
    end
  end

  describe AnyPayload do
    it 'should be of a kind' do
      expect(subject).to be_a Payload
    end
    it 'has args set to nil' do
      expect(subject.instance_variable_get(:@args)).to be_nil
    end
  end

  describe WithArgsSanitizer do
    it 'has arguments sanitized' do
      expect(subject.instance_variable_get(:@args)).to eq :some
    end
    it 'errors-out on get attempt' do
      expect { subject.get }.to raise_error Payload::NoPayloadSet
    end
  end

  describe CorrectPayload do
    it 'returns lambda' do
      expect(subject.get).to be_a Proc
      expect(subject.get.call).to eq :some
    end
  end
end
