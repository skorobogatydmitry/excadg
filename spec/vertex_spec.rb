# frozen_string_literal: true

require 'timeout'

module ExcADG
  # rubocop:disable Metrics/BlockLength
  # rubocop:disable Style/BlockDelimiters
  describe Vertex do
    before(:all) {
      Broker.run
    }

    context 'base features' do
      before(:all) {
        @a = Vertex.new payload: Payload::Example::Echo.new(args: :a)
        @b = Vertex.new payload: Payload::Example::Echo.new(args: :b), name: :custom_name
        @list = [@a, @b]
        sleep 0.1 until @list.all? { |e| Broker.data_store.key? e }
        @ra = @a.data.vertex
        @rb = @b.data.vertex
      }

      it 'has correct name' do
        expect(@a.name).to eq "v#{@a.number}".to_sym
        expect(@b.name).to eq :custom_name
      end
      it 'equals to its ractor' do
        expect(@a).to be_a Vertex
        expect(@ra).to be_a Vertex
        expect(@a).to eq @ra
      end
      it 'are not equal to each other' do
        expect(@a).not_to eq(@b)
        expect(@b).not_to eq(@a)
      end
      it 'should bookkeep all vertices' do
        expect(Broker.data_store.key?(@a)).to eq true
        expect(Broker.data_store.key?(@b)).to eq true
      end
      it 'subtracts from list' do
        expect(@list - [@a]).to eq [@b]
      end
    end
    context 'with correct payload' do
      subject { Vertex.new payload: Payload::Example::Echo.new }
      it 'should have correct info' do
        expect(subject.info.count).to eq 4
        expect(%i[terminated running blocking]).to include subject.status
        expect(subject.number).to be_a(Numeric)
      end
      it 'keeps returning data once finished' do
        sleep 0.5 until subject.state.eql? :done
        expect(subject.data.state).to eq :done
        expect(subject.data.data).to eq :ping
        expect(subject.data.data).to eq :ping
      end
    end
    context 'with timeout set' do
      subject { Vertex.new timeout: 0.1, payload: Payload::Example::Sleepy.new(args: 2) }

      it 'times out' do
        loop {
          sleep 0.1
          raise 'unexpected' if subject.state.eql? :done
          break if subject.state.eql? :failed
        }
        expect(subject.data.data).to be_a RTimeout::TimedOutError
      end
    end

    context 'with faulty payload' do
      subject { Vertex.new payload: Payload::Example::Faulty.new }
      it 'reaches failed state' do
        loop {
          sleep 0.1
          break if subject.state.eql? :failed
          raise 'it should not reach :done' if subject.state.eql? :done
        }
        expect(subject.data.data).to be_a StandardError
      end
    end
    context 'with dependencies' do
      subject(:dep1) { Vertex.new(payload: Payload::Example::Sleepy.new) }
      subject(:dep2) { Vertex.new(payload: Payload::Example::Sleepy.new) }
      subject(:stranger) { Vertex.new(payload: Payload::Example::Faulty.new) }
      subject { Vertex.new payload: Payload::Example::Sleepy.new, deps: [dep1, "v#{dep2.number}".to_sym] }

      it 'does not construct with incorrect dependency type' do
        expect { Vertex.new payload: Payload::Example::Echo.new, deps: [dep1, 'some'] }.to raise_error StandardError
      end

      it 'waits for dependencies' do
        sleep 0.1 until subject.state.eql? :new
        sleep 0.1 until [dep1, dep2].all? { |d| d.state.eql? :done } && stranger.state.eql?(:failed)
        expect(%i[new ready]).to include subject.state
        sleep 0.1 until subject.state.eql?(:done)
        expect(stranger.data.state).to eq :failed
      end
    end
    context 'with failing dependency' do
      subject(:dep1) { Vertex.new(payload: Payload::Example::Sleepy.new) }
      subject(:dep2) { Vertex.new(payload: Payload::Example::Faulty.new) }
      subject(:subj) { Vertex.new payload: Payload::Example::Echo.new, deps: [dep1, dep2] }
      it 'fails itself' do
        sleep 0.1 until subj.state.eql?(:failed)
        expect(dep2.data.state).to eq :failed
      end

      context 'with failing grand-dependency' do
        subject(:grandchild) { Vertex.new payload: Payload::Example::Echo.new, deps: [subj] }
        it 'fails too (in cascade)' do
          sleep 0.1 until grandchild.state.eql?(:failed)
          expect(subj.data.state).to eq :failed
        end
      end
    end
    context 'with deps data processing' do
      subject(:dep1) { Vertex.new(payload: Payload::Example::Echo.new) }
      subject(:dep2) { Vertex.new(payload: Payload::Example::Echo.new) }
      subject { Vertex.new payload: Payload::Example::Receiver.new, deps: [dep1, dep2] }
      it 'finishes successfully' do
        loop {
          break if subject.state.eql? :done
          raise if subject.state.eql? :failed

          sleep 0.5
        }
      end
    end
    context 'with conditional vertex' do
      subject(:dep1) { Vertex.new(payload: Payload::Example::Echo.new(args: :trigger)) }
      subject(:dep2) { Vertex.new(payload: Payload::Example::Echo.new(args: :trigger)) }
      subject { Vertex.new payload: Payload::Example::Condition.new, deps: [dep1, dep2] }
      it 'triggers another vertex' do
        loop {
          sleep 0.5
          break if subject.state.eql? :done
          raise if subject.state.eql? :failed
        }
        expect(subject.data.data).to be_a Vertex
      end
      context 'with threadkill dep' do
        subject(:dep3) { Vertex.new(payload: Payload::Example::Echo.new(args: :not_trigger)) }
        subject { Vertex.new payload: Payload::Example::Condition.new, deps: [dep1, dep2, dep3] }
        it 'does not trigger another vertex' do
          loop {
            sleep 0.5
            break if subject.state.eql? :done
            raise if subject.state.eql? :failed
          }
          expect(subject.data.data).to eq nil
        end
      end
    end

    context 'with loop vertex' do
      subject(:source) { Vertex.new payload: Payload::Example::Echo.new(args: [3, 2, 1]) }
      subject(:looper) { Vertex.new payload: Payload::Example::Loop.new, deps: [source] }

      it 'produces 3 new vertices' do
        loop {
          break if looper.state.eql? :done
          raise 'looper failed' if looper.state.eql? :failed
        }
        children = looper.data.data
        expect(children).to be_a Array
        expect(children.size).to eq 3
        loop {
          break if children.collect(&:state).all? :done
          raise 'one of children failed' if children.collect(&:state).any? :failed
        }
      end
    end

    context 'with many vertices', :perf do
      subject(:array) {
        Array.new(32) { Vertex.new payload: Payload::Example::Benchmark.new }
      }
      subject { Vertex.new payload: Payload::Example::Echo.new, deps: array }
      it 'should finish in timeout' do
        Timeout.timeout(90) { # timeout is speculative
          loop {
            sleep 2
            raise 'payload failed' if subject.data&.failed?
            break if subject.data&.done?
          }
        }
      end
    end
  end
  # rubocop:enable Style/BlockDelimiters
  # rubocop:enable Metrics/BlockLength
end
