# frozen_string_literal: true

module ExcADG
  describe Payload::Wrapper::Bin, uses: :payload do
    before {
      Broker.run
    }
    context 'echo temp file' do
      subject { Vertex.new payload: Payload::Wrapper::Bin.new(args: 'echo ${DEPS_DATAFILE}') }

      it 'echoes temp file name' do
        loop {
          sleep 0.1
          case subject&.state
          when :done then break
          when :failed then raise 'payload failed'
          end
        }
        expect(subject.data.data[:exitcode]).to eq 0
        expect(subject.data.data[:stdout]).to end_with "data.json\n"
      end
    end
    context 'with dependency data' do
      subject(:dep) { Vertex.new payload: Payload::Example::Echo.new(args: :pong) }

      subject { Vertex.new payload: Payload::Wrapper::Bin.new(args: 'cat ${DEPS_DATAFILE}'), deps: [dep] }
      it 'has deps JSON' do
        loop {
          sleep 0.1
          case subject&.state
          when :done then break
          when :failed then raise 'payload failed'
          end
        }
        expect(subject.data.data[:exitcode]).to eq 0
        parsed_output = JSON.parse subject.data.data[:stdout]
        expect(parsed_output.size).to eq 1
        expect(parsed_output.first['data']).to eq 'pong'
        expect(parsed_output.first['state']).to eq 'done'
        expect(parsed_output.first['name']).to start_with 'v'
      end
    end
  end

  describe Payload::Wrapper::Ruby, uses: :payload do
    before { Broker.run }
    subject { Vertex.new payload: Payload::Wrapper::Ruby.new(args: '-e "puts :pong"') }

    it 'echoes pong' do
      loop {
        sleep 0.1
        case subject&.state
        when :done then break
        when :failed then raise 'payload failed'
        end
      }
      expect(subject.data.data[:exitcode]).to eq 0
      expect(subject.data.data[:stdout]).to eq "pong\n"
    end
  end
end
