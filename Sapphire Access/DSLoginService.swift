//
//  DSLoginService.swift
//  Grade Checker
//
//  Created by Dhruv Sringari on 3/10/16.
//  Copyright © 2016 Dhruv Sringari. All rights reserved.
//

import Foundation
import Kanna
import CoreData
import MagicalRecord

class LoginService {
	var user: User
	let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
	let completion: (successful: Bool, error: NSError?) -> Void

	init(loginUserWithID userID: NSManagedObjectID, completionHandler completion: (successful: Bool, error: NSError?) -> Void) {
		user = NSManagedObjectContext.MR_defaultContext().objectWithID(userID) as! User
		self.completion = completion
		login()
	}
    
    // refreshes a logged in user
    init(refreshUserWithID userID: NSManagedObjectID, completion: (successful: Bool, error: NSError?) -> Void) {
        user = NSManagedObjectContext.MR_defaultContext().objectWithID(userID) as! User
        self.completion = completion
        
        let session = NSURLSession.sharedSession()
        let headers = [
            "content-type": "application/x-www-form-urlencoded"
        ]
        
        let postString = "javascript=true&j_username=" + self.user.username! + "&j_password=" + self.user.password! + "&j_pin=" + self.user.pin!
        let postData = NSMutableData(data: postString.dataUsingEncoding(NSUTF8StringEncoding)!)
        
        let request = NSMutableURLRequest(URL: NSURL(string: "http://192.168.1.3/CommunityWebPortal/Welcome.cfm.html")!,
                                          cachePolicy: .UseProtocolCachePolicy,
                                          timeoutInterval: 10)
        request.HTTPMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.HTTPBody = postData
        
        let dataTask = session.dataTaskWithRequest(request, completionHandler: { (data, response, error) -> Void in
            if (error != nil) {
                self.completion(successful: false, error: error)
                return
            } else {
                self.completion(successful: true, error: nil)
            }
        })
        
        dataTask.resume()
    }

	func login() {
		// Logout First to avoid problems with logging in with the parent account and then a student account
		logout { failed, error in
			if (failed) {
				self.completion(successful: false, error: error)
				return
			}
			let session = NSURLSession.sharedSession()
			let headers = [
				"content-type": "application/x-www-form-urlencoded"
			]

			let postString = "javascript=true&j_username=" + self.user.username! + "&j_password=" + self.user.password! + "&j_pin=" + self.user.pin!
			let postData = NSMutableData(data: postString.dataUsingEncoding(NSUTF8StringEncoding)!)

			let request = NSMutableURLRequest(URL: NSURL(string: "http://192.168.1.3/CommunityWebPortal/Welcome.cfm.html")!,
				cachePolicy: .UseProtocolCachePolicy,
				timeoutInterval: 10)
			request.HTTPMethod = "POST"
			request.allHTTPHeaderFields = headers
			request.HTTPBody = postData

			let dataTask = session.dataTaskWithRequest(request, completionHandler: { (data, response, error) -> Void in
				if (error != nil) {
					self.completion(successful: false, error: error)
					return
				} else {
					self.getMainPageHtml()
				}
			})

			dataTask.resume()
		}
	}

	func logout(completionHandler: (failed: Bool, error: NSError?) -> Void) {
		let session = NSURLSession.sharedSession()
		let request = NSURLRequest(URL: NSURL(string: "http://192.168.1.3/CommunityWebPortal/Welcome.cfm.html?logout=1")!, cachePolicy: .UseProtocolCachePolicy, timeoutInterval: 10)

		let logoutTask = session.dataTaskWithRequest(request, completionHandler: { data, response, error in
			if (error != nil) {
				completionHandler(failed: true, error: error)
				return
			}
			completionHandler(failed: false, error: nil)
		})
		logoutTask.resume()
	}

	// Because of sapphire's strange cookie detection, we have to make a seperate request for the main page. Depending on the title of the page, we can determine whether the user has inputed the correct credentials.

	private func getMainPageHtml() {

		let request = NSMutableURLRequest(URL: NSURL(string: "http://192.168.1.3/CommunityWebPortal/Welcome.cfm.html")!,
			cachePolicy: .UseProtocolCachePolicy,
			timeoutInterval: 10.0)
		request.HTTPMethod = "GET"

		let session = NSURLSession.sharedSession()
		let dataTask = session.dataTaskWithRequest(request, completionHandler: { (data, response, error) -> Void in
			if (error != nil) {
				self.completion(successful: false, error: error)
			} else {
				if let html: String = NSString(data: data!, encoding: NSUTF8StringEncoding) as? String {

					if let doc = Kanna.HTML(html: html, encoding: NSUTF8StringEncoding) {

						switch (doc.title!) {
							// This user is a student account so it has one student.
						case " Student Backpack - Sapphire Community Web Portal ":
							// Retrieve student information from backpack screen
							
							let i: String = doc.xpath("//*[@id=\"leftPipe\"]/ul[2]/li[4]/a")[0]["title"]!.stringByReplacingOccurrencesOfString(".html", withString: "") // TODO: REMOVE ME
							let id = i.componentsSeparatedByString("=")[1]
                            var student = Student.MR_findFirstByAttribute("id", withValue: id, inContext: NSManagedObjectContext.MR_defaultContext())
                            if student == nil {
                                student = Student.MR_createEntityInContext(NSManagedObjectContext.MR_defaultContext())
                            }
							let name: String = doc.xpath("//*[@id=\"leftPipe\"]/ul[1]/li/a")[0]["title"]!
							let g: String = doc.xpath("//*[@id=\"leftPipe\"]/ul[1]/li/div[1]")[0]["title"]!
							let grade = g.componentsSeparatedByCharactersInSet(NSCharacterSet(charactersInString: "1234567890").invertedSet).joinWithSeparator("")
							let school: String = doc.xpath("//*[@id=\"leftPipe\"]/ul[1]/li/div[2]")[0]["title"]!

							student?.id = id
							student?.name = name
							student?.grade = grade
							student?.school = school
							student?.user = self.user
							NSManagedObjectContext.MR_defaultContext().MR_saveToPersistentStoreAndWait()
                            self.completion(successful: true, error: nil)
							// This user is a parent
						case " Welcome - Sapphire Community Web Portal ":
                            
                            // Clear Old Students
                            // Todo: Stop Deleting Entities

							var ids: [String] = []
							var names: [String] = []
                            var students: [Student] = []
							for e in doc.xpath("//*[@id=\"leftPipe\"]/ul//li/a") {
								var id = e["href"]!
								id = id.componentsSeparatedByString("=")[1]
                                id = id.stringByReplacingOccurrencesOfString(".html", withString: "") // TODO: REMOVE ME WHEN RELASEING
                                if let oldStudent = Student.MR_findFirstByAttribute("id", withValue: id, inContext: NSManagedObjectContext.MR_defaultContext()) {
                                    students.append(oldStudent)
                                } else {
                                    if let newStudent = Student.MR_createEntityInContext(NSManagedObjectContext.MR_defaultContext()) {
                                        students.append(newStudent)
                                    }
                                }
								let name = e["title"]!
								ids.append(id)
								names.append(name)
							}

							var grades: [String] = []
							for e in doc.xpath("//*[@id=\"leftPipe\"]/ul//li/div[1]") {
								let g = e["title"]!
								let grade = g.componentsSeparatedByCharactersInSet(NSCharacterSet(charactersInString: "1234567890").invertedSet).joinWithSeparator("")
								grades.append(grade)
							}

							var schools: [String] = []
							for e in doc.xpath("//*[@id=\"leftPipe\"]/ul//li/div[2]") {
								let school = e["title"]!
								schools.append(school)
							}

							for index in 0 ..< ids.count {
								students[index].id = ids[index]
								students[index].name = names[index]
								students[index].grade = grades[index]
								students[index].school = schools[index]
								students[index].user = self.user
							}
							NSManagedObjectContext.MR_defaultContext().MR_saveToPersistentStoreAndWait()
							self.completion(successful: true, error: nil)
                        // Failed to Login
						default:
							self.completion(successful: false, error: badLoginError)
						}
					} else {
						self.completion(successful: false, error: unknownResponseError)
					}
				} else {
					self.completion(successful: false, error: unknownResponseError)
				}
			}
		})

		dataTask.resume()
	}
}