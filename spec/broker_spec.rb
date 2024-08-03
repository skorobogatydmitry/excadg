# frozen_string_literal: true

module ExcADG
  describe Broker do
    context 'for ask' do
      subject(:dvertex) { double Vertex }
      subject(:dractor_cls) { class_double(Ractor).as_stubbed_const(transfer_nested_constants: true) }
      subject(:dmain_ractor) { double Ractor }
      subject(:dcurr_ractor) { double Ractor }
      subject(:get_request) { Request::GetStateData.new }

      before {
        # stub Ractor's messaging
        allow(dvertex).to receive(:is_a?).with(Vertex) { true }
        allow(Vertex).to receive(:===).with(dvertex) { true }
        allow(dractor_cls).to receive(:current).and_return dcurr_ractor
        allow(dractor_cls).to receive(:main).and_return dmain_ractor
      }

      it 'fails on incorrect requests type' do
        ErrorCatcher.new { Broker.ask :some }.catch { |exc|
          expect(exc).to be_a Broker::UnknownRequestType
        }
      end

      it 'processes a correct ask' do
        allow(dractor_cls).to receive(:receive).and_return :stubbed_answer
        expect(dmain_ractor).to receive(:send).with(get_request).exactly 1
        Broker.ask get_request
      end

      it 'fails on message send errors' do
        error = StandardError.new
        expect(dmain_ractor).to receive(:send).with(get_request).and_raise error
        ErrorCatcher.new { Broker.ask get_request }.catch { |exc|
          expect(exc).to be_a Broker::CantSendRequest
          expect(exc.cause).to eq error
        }
      end

      it 're-raises errors received' do
        error = StandardError.new
        expect(dmain_ractor).to receive(:send).with(get_request).exactly 1
        expect(dractor_cls).to receive(:receive).with(no_args).and_return error
        ErrorCatcher.new { Broker.ask get_request }.catch { |exc|
          expect(exc).to eq error
        }
      end
    end

    context 'for requests processing', uses: :broker_data do
      subject(:ddata_store) { double DataStore }
      subject(:dractor_cls) { class_double(Ractor).as_stubbed_const(transfer_nested_constants: true) }
      subject(:dcurr_ractor) { double Ractor }

      before {
        Broker.instance_variable_set :@data_store, ddata_store
        allow(dractor_cls).to receive(:current).and_return dcurr_ractor
      }

      context 'with wrong request' do
        subject(:drequest) { double Object }
        before {
          allow(dractor_cls).to receive(:receive).with(no_args).and_return drequest
          allow(drequest).to receive(:self).with(no_args).and_return dcurr_ractor
        }

        it 'throws error' do
          expect(dcurr_ractor).to receive(:send)
            .with(satisfy { |args|
                    expect(args).to be_a Broker::RequestProcessingFailed
                    expect(args.message).to eq 'ExcADG::Broker::UnknownRequestType'
                  })
          Broker.send :process_request
        end
      end

      context 'with get request' do
        subject(:drequest) { double Request::GetStateData }

        before {
          allow(Request::GetStateData).to receive(:===).with(drequest).and_return true
          allow(dractor_cls).to receive(:receive).with(no_args).and_return drequest
          allow(drequest).to receive(:self).with(no_args).and_return dcurr_ractor
        }
        it 'processes requests without filters' do
          allow(ddata_store).to receive(:to_a).and_return %i[some other]
          expect(drequest).to receive(:filter?).and_return false
          expect(dcurr_ractor).to receive(:send)
            .with %i[some other]
          Broker.send :process_request
        end
        it 'processes request with filters' do
          allow(ddata_store).to receive(:'[]').and_return :some
          expect(drequest).to receive(:filter?).and_return true
          expect(drequest).to receive(:deps).and_return [:other]
          expect(dcurr_ractor).to receive(:send)
            .with %i[some]
          Broker.send :process_request
        end

        it 'fails on request processing' do
          error = StandardError.new
          expect(drequest).to receive(:filter?).and_raise error
          expect(dcurr_ractor).to receive(:send)
            .with(satisfy { |args|
                    expect(args).to be_a Broker::RequestProcessingFailed
                    expect(args.message).to eq 'StandardError'
                  })
          Broker.send :process_request
        end
        it 'tracks request' do
          deps = :mocked_deps
          dvtracker = double(VTracker)
          Broker.instance_variable_set :@vtracker, dvtracker
          expect(dvtracker).to receive(:track).with(dcurr_ractor, deps).exactly 1

          allow(ddata_store).to receive(:to_a).and_return %i[some other]
          expect(drequest).to receive(:filter?).and_return false
          expect(drequest).to receive(:deps).and_return deps
          expect(dcurr_ractor).to receive(:send)
          Broker.send :process_request
        end
      end

      context 'with update request' do
        subject(:drequest) { double Request::Update }
        subject(:dvstate_data) { double VStateData::Full }
        subject(:dcurr_vertex) { double Vertex }

        before {
          allow(Request::Update).to receive(:===).with(drequest) { true }
          allow(dractor_cls).to receive(:receive).with(no_args).and_return drequest
          allow(drequest).to receive(:self).with(no_args).and_return dcurr_ractor
          allow(drequest).to receive(:data).with(no_args).and_return dvstate_data
          allow(dvstate_data).to receive(:vertex).with(no_args).and_return dcurr_vertex
        }

        it 'updates data store' do
          expect(ddata_store).to receive(:<<).with dvstate_data
          expect(dcurr_ractor).to receive(:send)
            .with true
          Broker.send :process_request
        end

        it 'tracks request' do
          dvtracker = double(VTracker)
          Broker.instance_variable_set :@vtracker, dvtracker
          expect(dvtracker).to receive(:track).with(dcurr_ractor).exactly 1

          expect(ddata_store).to receive(:<<).with dvstate_data
          expect(dcurr_ractor).to receive(:send)
            .with(satisfy { |args|
                    expect(args).to eq true
                  })
          Broker.send :process_request
        end
      end

      context 'with add vertex request' do
        subject(:drequest) { double Request::AddVertex }
        subject(:dvstate_data) { double VStateData::Full }
        subject(:dnew_vpayload) { double Payload }
        subject(:dvertex_cls) { class_double(Vertex).as_stubbed_const(transfer_nested_constants: true) }
        subject(:dvresult) { double Vertex }

        before {
          allow(Request::AddVertex).to receive(:===).with(drequest) { true }
          allow(dractor_cls).to receive(:receive).with(no_args).and_return drequest
          allow(drequest).to receive(:self).with(no_args).and_return dcurr_ractor
          allow(drequest).to receive(:data).with(no_args).and_return dvstate_data
          allow(drequest).to receive(:payload).with(no_args).and_return dnew_vpayload
        }
        it 'makes a vertex' do
          expect(dcurr_ractor).to receive(:send)
            .with dvresult
          expect(dvertex_cls).to receive(:new)
            .with(satisfy { |args|
              expect(args[:payload]).to eq dnew_vpayload
              expect(args[:deps].first).to eq dcurr_ractor
            }).and_return dvresult
          Broker.send :process_request
        end

        it 'tracks request' do
          dvtracker = double(VTracker)
          Broker.instance_variable_set :@vtracker, dvtracker
          expect(dvtracker).to receive(:track).with(dvresult).exactly 1

          expect(dcurr_ractor).to receive(:send)
            .with dvresult
          expect(dvertex_cls).to receive(:new)
            .with(satisfy { |args|
              expect(args[:payload]).to eq dnew_vpayload
              expect(args[:deps].first).to eq dcurr_ractor
            }).and_return dvresult
          Broker.send :process_request
        end
      end
    end

    context 'for run' do
      it 'spawns request processing thread' do
        expect(Broker.run).to be_a Thread
      end
      it 'does not enables tracking by default' do
        Broker.run
        expect(Broker.vtracker).to be_nil
      end
      context 'with double spawn' do
        subject(:first) { Broker.run }
        subject(:second) { Broker.run }

        it 'returns the same thread' do
          expect(first).to eq second
        end
      end
      context 'with enabled tracking' do
        before { Broker.run track: true }
        it 'has vtracker' do
          expect(Broker.vtracker).to be_a VTracker
        end
      end
    end

    context 'for wait_all', uses: :broker_data do
      subject(:dvertex) { double Vertex }
      subject(:done_state) { VStateData::Full.new(state: :done, name: :foo, data: nil, vertex: dvertex) }
      subject(:failed_state) { VStateData::Full.new(state: :failed, name: :bar, data: nil, vertex: dvertex) }
      subject(:undone_state) { VStateData::Full.new(state: :some, name: :baz, data: nil, vertex: dvertex) }
      subject(:ddata_store) { double DataStore }

      before {
        allow(dvertex).to receive(:is_a?).with(Vertex).and_return true
        allow(dvertex).to receive(:is_a?).with(Array).and_return false
        allow(Vertex).to receive(:===).with(dvertex).and_return true
        Broker.instance_variable_set :@data_store, ddata_store
      }

      it 'waits if there are no vertices yet' do
        expect(ddata_store).to receive(:empty?).and_return(true).at_least 1
        t = Broker.wait_all period: 0.2, timeout: 1
        expect { t.join }.to raise_error Timeout::Error
      end

      it 'waits for all vertices to report terminal state' do
        expect(ddata_store).to receive(:empty?).and_return(false).at_least 1
        expect(ddata_store).to receive(:to_a).and_return(
          [done_state, undone_state, failed_state],
          [done_state, undone_state],
          [undone_state, failed_state],
          [done_state, failed_state]
        )
        t = Broker.wait_all period: 0.1, timeout: 2
        expect(t.alive?).to eq true
        t.join
      end

      it 'times out' do
        expect(ddata_store).to receive(:empty?).and_return(false).at_least 1
        expect(ddata_store).to receive(:to_a).and_return([undone_state]).at_least 5
        t = Broker.wait_all timeout: 1, period: 0.1
        expect(t.alive?).to eq true
        expect { t.join }.to raise_error Timeout::Error
      end
    end
  end
end
