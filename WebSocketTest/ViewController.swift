//
//  ViewController.swift
//  WebSocketTest
//
//  Created by Ori Chajuss on 12/02/2018.
//  Copyright © 2018 Ori Chajuss. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa

class ViewController: UIViewController {
    
    // MARK: - UIElements
    @IBOutlet weak var serverButton: UIButton!
    @IBOutlet weak var clientButton: UIButton!
    @IBOutlet weak var stopButton: UIButton!
    
    // MARK: - Members
    private var testServer: TestServer?
    private var testClient: TestClient?
    
    //MARK: - RxElements
    private let disposeBag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupServerButtonTapped()
        setupClientButtonTapped()
        setupStopButtonTapped()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - RxCocoa functions
    private func setupServerButtonTapped() {
        serverButton.rx.tap.subscribe({ [unowned self] _ in
            self.clientButton.isHidden = true
            self.serverButton.isHidden = true
            self.stopButton.isHidden = false
            self.testServer = TestServer()
        }).disposed(by: disposeBag)
    }

    private func setupClientButtonTapped() {
        clientButton.rx.tap.subscribe({ [unowned self] _ in
            self.serverButton.isHidden = true
            self.clientButton.isHidden = true
            self.stopButton.isHidden = false
            self.testClient = TestClient()
        }).disposed(by: disposeBag)
    }
    
    private func setupStopButtonTapped() {
        stopButton.rx.tap.subscribe({ [unowned self] _ in
            self.serverButton.isHidden = false
            self.clientButton.isHidden = false
            self.stopButton.isHidden = true
            self.testServer?.stopServer()
            self.testClient?.stopClient()
        }).disposed(by: disposeBag)
    }
}

