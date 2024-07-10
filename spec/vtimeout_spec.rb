# frozen_string_literal: true

require 'timeout'

module ExcADG
  describe VTimeout do
    it 'allows all nils' do
      expect(subject.global).to be nil
      expect(subject.deps).to be nil
      expect(subject.payload).to be nil
    end

    it 'sets timeouts' do
      subj = VTimeout.new global: 3, deps: 2, payload: 1
      expect(subj.global).to be 3
      expect(subj.deps).to be 2
      expect(subj.payload).to be 1
    end

    it 'fails on too short payload' do
      expect { VTimeout.new global: 2, deps: 2, payload: 1 }.to raise_error StandardError
    end

    it 'allows to set any timeouts on empty global' do
      subj = VTimeout.new deps: 2, payload: 1
      expect(subj.global).to be nil
      expect(subj.deps).to be 2
      expect(subj.payload).to be 1
    end
  end
end
