# frozen_string_literal: true

module ExcADG
  describe RTimeout do
    it 'does not times out if payload finishes in time' do
      result = RTimeout.await(timeout: 1) { :some }
      expect(result).to eq :some
    end

    it 'times out if payload does not finishes in time' do
      expect { RTimeout.await(timeout: 0.1) { sleep 1 } }.to raise_error RTimeout::TimedOutError
    end
    it 're-raises internal exceptions' do
      ErrorCatcher.new { RTimeout.await(timeout: 1) { raise 'internal error' } }.catch { |exc|
        expect(exc).to be_a StandardError
        expect(exc.message).to eq 'internal error'
      }
    end
    it 'works in ractor', uses: :ractor do
      r = Ractor.new {
        RTimeout.await(timeout: 1) {
          :some
        }
      }
      expect(r.take).to eq :some
    end
  end
end
