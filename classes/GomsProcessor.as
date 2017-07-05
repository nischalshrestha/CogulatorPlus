﻿/*******************************************************************************
 * This is the copyright work of The MITRE Corporation, and was produced for the
 * U. S. Government under Contract Number DTFAWA-10-C-00080.
 *
 * For further information, please contact The MITRE Corporation, Contracts Office,
 * 7515 Colshire Drive, McLean, VA  22102-7539, (703) 983-6000.
 *
 * Copyright 2014 The MITRE Corporation
 *
 * Approved for Public Release; Distribution Unlimited. 14-0584
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 ******************************************************************************/

package classes {
	import flash.utils.Dictionary;
	import classes.SyntaxColor;
	import classes.TimeObject;
	import classes.Step;
	import classes.StringUtils;
	import com.inruntime.utils.*;


	public class GomsProcessor {
		private static var $: Global = Global.getInstance();

		private static var cntrlmthds: Array; //list of methods in the control loop for overview timeline
		private static var allmthds: Array;
		private static var steps: Array;
		private static var intersteps: Array; //interleaved steps
		private static var thrdOrdr: Array; //an order of threads for gantt chart time line annotation

		private static var threadTracker: Dictionary; // tracks the active method for each thread
		private static var resourceAvailability: Dictionary;
		private static var threadAvailability: Dictionary;
		private static var goalIndex: Dictionary;


		private static var newThreadNumber: int; // = 0; //used as a thread name for "Also" when one is not provided

		private static var maxEndTime: Number; // = 0;
		private static var cycleTime: Number;


		private static var stateTable: Dictionary = new Dictionary();


		public static function processGOMS(): Array {
			maxEndTime = 0;
			cycleTime = 0; //ms. 50 ms Based on production rule cycle time.  Bovair & Kieras/Card, Moran & Newell
			newThreadNumber = 0;

			cntrlmthds = new Array();
			allmthds = new Array();
			steps = new Array();
			intersteps = new Array();
			thrdOrdr = new Array();

			threadTracker = new Dictionary(); //hashmap that tracks that active goal for each thread
			resourceAvailability = new Dictionary();
			threadAvailability = new Dictionary();
			goalIndex = new Dictionary();

			//(<resource name>, <time resource comes available>)
			var to: TimeObject = new TimeObject(0, 0);
			var verbalcomsArray: Array = new Array(to);
			var seeArray: Array = new Array(to);
			var cognitiveArray: Array = new Array(to);
			var handsArray: Array = new Array(to);
			var branchArray: Array = new Array(to);
			resourceAvailability["verbalcoms"] = verbalcomsArray;
			resourceAvailability["see"] = seeArray;
			resourceAvailability["cognitive"] = cognitiveArray;
			resourceAvailability["hands"] = handsArray;


			for (var key: Object in $.errors) delete $.errors[key]; //clear out all $.errors
			for (var key: Object in $.stateTable) delete $.stateTable[key]; // clear out all $.stateTable

			SyntaxColor.typing = false;
			//trace("state table ")
			generateStepsArray();

			trace("generateStepsArray done");


			if (steps.length > 0) processStepsArray(); //processes and then interleaves steps

			trace("processStepsArray done");
			

			return (new Array(maxEndTime, thrdOrdr, threadAvailability, intersteps, allmthds, cntrlmthds));
		}


		private static function generateStepsArray() {
			var codeLines: Array = $.codeTxt.text.split("\r");
			var beginIndex: int = 0;
			var endIndex: int = codeLines[0].length;
			stateTable = new Dictionary();
			var jumps:int = 0;

			//Color all lines since GoTo skips some lines, but we don't want them to be gray. 
			//SyntaxColor.solarizeAll();
			
			
			for (var lineIndex: int = 0; lineIndex < codeLines.length; lineIndex++) {
				var line = codeLines[lineIndex];
				//beginIndex = findBeginningIndex(codeLines, lineIndex);
				endIndex = beginIndex + line.length;
				goalIndex = indexGoalLines(codeLines);
				if (StringUtils.trim(line) != "") {
					var syntaxArray:Array = SyntaxColor.solarizeLineNum(lineIndex, beginIndex, endIndex);

					var indentCount: int = syntaxArray[0];
					var stepOperator: String = syntaxArray[1];
					var stepLabel: String = trimLabel(syntaxArray[2]);
					var stepTime: String = syntaxArray[3];
					var chunkNames: Array = syntaxArray[7];

					/* 
					trace("indentCount: "+indentCount);
					trace("stepOperator: "+stepOperator);
					trace("stepLabel: "+stepLabel);
					trace("stepTime: "+stepTime);
					trace("chunkNames: "+chunkNames.toString());*/


					var methodGoal, methodThread:String;
					if (stepOperator != "goal" && stepOperator != "also") {
						var goalAndThread:Array = findGoalAndThread(indentCount); //determine the operator and thread
						methodGoal = goalAndThread[0];
						methodThread = goalAndThread[1];
						//trace("not a goal or alos operator "+stepOperator);
					} else {
						methodGoal = stepLabel;
						if (syntaxArray[4] == "!X!X!") {
							methodThread = String(newThreadNumber);
							newThreadNumber++;
						} else {
							methodThread = syntaxArray[4];
						}
	
						allmthds.push(stepLabel); //for charting in GanttChart
						if (indentCount == 1) cntrlmthds.push(stepLabel);  //for charting in GanttChart
					}
										
					if (syntaxArray[5] == false && stepOperator.length > 0) { //if there are no errors in the line and an operator exists...
						var s:Step = new Step (indentCount, methodGoal, methodThread, stepOperator, getOperatorTime(stepOperator, stepTime, stepLabel), getOperatorResource(stepOperator), stepLabel, lineIndex, 0, chunkNames);				
						//trace("pushing step");
						//trace("step operator: "+stepOperator);
						steps.push(s); 
					}

					/*
					var frontTrimmedLine: String = trimIndents(codeLines[lineIndex]);
					var tokens: Array = frontTrimmedLine.split(' ');
					var operator = trimColon(tokens[0].toLowerCase());
					tokens[0] = operator;
					switch (operator) {
						case "createstate":
							if (hasError(tokens, codeLines)) {
								SyntaxColor.ErrorColorLine(lineIndex);
							} else {
								createState(tokens[1], tokens[2]);
							}
							break;
						case "setstate":
							if (hasError(tokens, codeLines)) {
								SyntaxColor.ErrorColorLine(lineIndex);
							} else {
								setState(tokens);
							}
							break;
						case "if":
							if (hasError(tokens, codeLines)) {
								SyntaxColor.ErrorColorLine(lineIndex);
							} else {
								//should return int of next line to be processed based on the resolution
								//of the if statement.
								lineIndex = nextIfLine(codeLines, lineIndex);
							}
							break;
						case "endif":
							if (hasError(tokens, codeLines)) {
								SyntaxColor.ErrorColorLine(lineIndex);
							}
							//ignore EndIfs, but are useful in processing original statement.
							break;
						case "goto":
							//Checks for infinite loops and syntax errors
							//Jumps are limited to 25, after which all jumps will be considered errors and not processed.
							if (jumps > 1 || hasError(tokens, codeLines)) {
								SyntaxColor.ErrorColorLine(lineIndex);
							} else {
								//line should be in the form "GoTo Goal: goal_name" (name can contain spaces)
								var goalTokens = frontTrimmedLine.split("Goal: ");
								var goalName = goalTokens[1];
								goalIndex = indexGoalLines(codeLines);
								if(goalIndex[goalName] !== undefined){
									lineIndex = goalIndex[goalName] - 1;
									jumps++;
								} else {
									SyntaxColor.ErrorColorLine(lineIndex);
								}
							}
							break;
						default:
							var syntaxArray: Array = SyntaxColor.solarizeLineNum(lineIndex, beginIndex, endIndex);
							processBaseCogulatorLine(syntaxArray, lineIndex);
					}
					*/
				}
				beginIndex = endIndex + 1;
			}
			removeGoalSteps();
			//removeBranchSteps();
			setPrevLineNo();
			//trace("finish generateStepsArray");

		}

		// ** This might not be needed after refactor as Syntax Color will have ways to do this **
		//Purpose:  Find the "beginIndex" used in process steps array. should be the sum 
		//			of the length of all lines that came before. Necessary for line jumping
		// 			for if's and goTos.
		//
		//Input: Array lines: all lines in the editor (codeLines from generateStepArray).
		//Output: int beginIndex: the correct index to feed solarize function
		private static function findBeginningIndex(lines: Array, lineNumber): int {
			var beginIndex: int = 0;
			for (var i: int = 0; i < lineNumber; i++) {
				beginIndex += lines[i].length + 1; //Plus new line character
			}
			return beginIndex;
		}

	    // TODO: Eventually remove this
		//Purpose: Creates the stepArray to be processed.
		//Input: Array syntaxArray: created from solarizeLine().
		//		 int: lineIndex (current line being processed)
		//Output: none
		//Notes: created for Cog+ functionality.  Code was extracted from processStepArray.
		private static function processBaseCogulatorLine(syntaxArray: Array, lineIndex: int) {
			var indentCount: int = syntaxArray[0];
			var stepOperator: String = syntaxArray[1];
			var stepLabel: String = trimLabel(syntaxArray[2]);
			var stepTime: String = syntaxArray[3];
			var chunkNames: Array = syntaxArray[7];

			var methodGoal, methodThread: String;
			if (stepOperator != "goal" && stepOperator != "also") {
				var goalAndThread: Array = findGoalAndThread(indentCount); //determine the operator and thread
				methodGoal = goalAndThread[0];
				methodThread = goalAndThread[1];
			} else {
				methodGoal = stepLabel;
				if (syntaxArray[4] == "!X!X!") {
					methodThread = String(newThreadNumber);
					newThreadNumber++;
				} else {
					methodThread = syntaxArray[4];
				}

				allmthds.push(stepLabel); //for charting in GanttChart
				if (indentCount == 1) cntrlmthds.push(stepLabel); //for charting in GanttChart
			}

			if (syntaxArray[5] == false && stepOperator.length > 0) { //if there are no errors in the line and an operator exists...
				var s: Step = new Step(indentCount, methodGoal, methodThread, stepOperator, getOperatorTime(stepOperator, stepTime, stepLabel), getOperatorResource(stepOperator), stepLabel, lineIndex, 0, chunkNames);
				steps.push(s);
			}
		}


		private static function removeGoalSteps() {
			for (var i: int = steps.length - 1; i > -1; i--) {
				if (steps[i].operator == "goal" || steps[i].operator == "also") steps.splice(i, 1);
			}
			trace("steps left in array "+steps.length);
		}


		// IN PROGRESS
		private static function removeBranchSteps() {
			var unevaluatedSteps:Array = new Array();
			var removedCount:int = 0
			var endifIndex:int = 0;
			//steps.clear();
			for (var i: int = steps.length - 1; i > -1; i--) {
				trace("operator to remove "+steps[i].operator +", lineNo "+steps[i].lineNo);
				if (SyntaxColor.branches.indexOf(steps[i].operator) != -1) {
					if (unevaluatedSteps.indexOf(steps[i].lineNo) != -1) {
						steps.splice(i, 1);
						removedCount++;
					} else if (steps[i].operator == "if") {
						// if you have an If, make sure to delete steps within if false
						var ifLine = steps[i].lineNo;
						trace("ifLine "+ifLine)
						var lines: Array = $.codeTxt.text.split("\r");
						trace("trimmed ifline "+trimIndents(lines[steps[i].lineNo]));
						if (!evaluateIfStatement(trimIndents(lines[steps[i].lineNo]))) {
							trace("false");
							var endIfIndex = findFirstEndIf(steps[i].lineNo);
							for (var j = endIfIndex; j > ifLine; j--) {
								if (unevaluatedSteps.indexOf(j) == -1){
									unevaluatedSteps.push(j);
									trace("pushing step to remove "+j);
								}
							}
						}
						steps.splice(i, 1);
						removedCount++;
						trace(" final i "+i);
					} else if (steps[i].operator != "endif") {
						steps.splice(i, 1);
						removedCount++;
					}
					//trace("branch operator to remove "+steps[i].operator);
				}
				// else {
					//trace("branch operator to remove else "+steps[i].operator);
				//}
				
			}
			trace("steps left in array "+steps.length);
		}

		private static function setPrevLineNo() {
			//steps[0] is set to 0 by default, all others should be updated
			for (var i: int = 1; i < steps.length; i++) {
				steps[i].prevLineNo = steps[i - 1].lineNo;
			}
		}


		//*** Second Pass interleaves the steps according to thread name
		private static function processStepsArray() {
			do {
				var step: Step = steps[0]; //look at the first step in the steps arraylist
				threadTracker[step.thred] = step.goal;


				//iterate through each thread in the tracker, and place one step from each active thread/goal
				for (var myKy: String in threadTracker) {
					var goal: String = threadTracker[myKy];
					var thred: String = myKy;
					trace("step and thread "+step.operator + ", "+step.thred);
					interleaveStep(thred, goal);
				}
			} while (steps.length > 0);

			thrdOrdr.push("base");
			for (var myKey: String in threadTracker) {
				var thread: String = myKey;
				if (thread != "base") thrdOrdr.push(thread);
			}
			
		}


		private static function interleaveStep(thread: String, goal: String) {
			for (var i: int = 0; i < steps.length; i++) {
				var step: Step = steps[i];
				if (thread == "base") {
					if (step.thred == "base") {
						var t: Array = findStartEndTime(step);
						step.srtTime = t[0];
						step.endTime = t[1];
						intersteps.push(step);
						steps.splice(i, 1);
						break;
					}
				} else {
					if (step.thred == thread && step.goal == goal) {
						var th: Array = findStartEndTime(step);
						step.srtTime = th[0];
						step.endTime = th[1];
						intersteps.push(step);
						steps.splice(i, 1);
						break;
					}
				}

			}
		}


		private static function findStartEndTime(step: Step): Array {

			var resource: String = step.resource;
			var thread: String = step.thred;
			var method: String = step.goal
			var stepTime: Number = step.time

			var zerodTO: TimeObject = new TimeObject(0, 0);
			var resourceTO: TimeObject;
			var threadTO: TimeObject;
			var methodTO: TimeObject;
			var resourceTime: Number = 0;
			var threadTime: Number = 0;
			var methodTime: Number = 0;

			if (resource == "speech" || step.resource == "hear") resource = "verbalcoms";
			if (threadAvailability[thread] == null) {
				var prevLineNumberTime = getPreviousLineTime(step.prevLineNo);
				zerodTO.et = prevLineNumberTime;
				threadAvailability[thread] = zerodTO;
			}
			threadTO = threadAvailability[thread];
			threadTime = threadTO.et;


			//var startTime:Number = Math.max(threadTime, methodTime);
			var startTime: Number = threadTime;
			var endTime: Number = startTime + stepTime + cycleTime;

			trace("found end time for "+step.operator);

			startTime = getResourceAvailability(resource, startTime, endTime, stepTime);


			endTime = startTime + stepTime + cycleTime;

			//store the results for the next go round
			threadAvailability[thread] = new TimeObject(startTime, endTime);


			var reslt: Array = new Array();
			reslt[0] = startTime;
			reslt[1] = endTime;

			return reslt;
		}


		private static function getPreviousLineTime(lineNoToFind: int): Number {
			//retrieve the start time for the step previous to the current one
			for each(var step in intersteps) {
				if (step.lineNo == lineNoToFind) {
					return step.srtTime;
				}
			}

			//this should never happen...
			return 0;
		}

		private static function getResourceAvailability(resource: String, startTime: Number, endTime: Number, stepTime: Number): Number {
			//pull the resource array of TimeObjects associated with the resource
			var resourceArray: Array = resourceAvailability[resource]; //time the resource becomes available
			trace("getting resource "+resourceArray);
			for (var i: int = 0; i < resourceArray.length - 1; i++) {
				if (resourceArray[i].et < resourceArray[i + 1].st) { //this means there's a gap - it's worth digging further
					if (startTime >= resourceArray[i].et) { //if the resource availability occurs after the earliest possible start time, it's worth digging further
						if (endTime <= resourceArray[i + 1].st) { //... check to see if there's a gap large enough to insert the operator
							var gapTO: TimeObject = new TimeObject(Math.max(startTime, resourceArray[i].et), Math.max(endTime, resourceArray[i].et + stepTime + cycleTime));
							resourceArray.splice(i, 0, gapTO);
							return (Math.max(gapTO.st, startTime));
						}
					}
				}
			}


			var to: TimeObject = new TimeObject(Math.max(startTime, resourceArray[resourceArray.length - 1].et), Math.max(endTime, resourceArray[resourceArray.length - 1].et + stepTime + cycleTime));
			resourceArray.push(to);
			return (Math.max(to.st, startTime));
		}


		private static function findGoalAndThread(indents: int): Array {
			var goalAndThread: Array = new Array();

			//start last line entered in steps and search backard until you find the goal for line being processed
			if (steps.length > 0) {
				for (var i: int = steps.length - 1; i >= 0; i--) {
					if (steps[i].indentCount == indents - 1) { //if this step exists one level above the line being processed in the hiearchy
						if (steps[i].operator == "goal") {
							goalAndThread[0] = steps[i].goal;
							goalAndThread[1] = "base";
							return goalAndThread;
						} else if (steps[i].operator == "also") {
							goalAndThread[0] = steps[i].goal;
							goalAndThread[1] = steps[i].thred;
							return goalAndThread;
						}
					}
				}
			}

			goalAndThread[0] = "none";
			goalAndThread[1] = "base" // a thread without a goal should return base
			return goalAndThread;
		}


		private static function trimLabel(lbl: String): String {
			//trim white space from beginning of label
			while (lbl.substr(lbl.length - 1, 1) == " ") lbl = lbl.substr(0, lbl.length - 1);
			return lbl;
		}


		private static function itIsAStepOperator(stepOperator: String): Boolean {
			//if the operator exists, return true
			for each(var operator in $.operatorArray) {
				if (stepOperator.toLowerCase() == operator.appelation.toLowerCase()) return true;
			}
			return false; //could not find a match
		}


		private static function getOperatorTime(operatorStr: String, customTime: String, lbl: String): Number {
			//match the operator string to a defined operator
			//var operatorInfo:Array = new Array({resource: "", appelation: "", time: "", description: "", labelUse: ""});
			var operatorObj: Object = new Object();
			for each(var oprtr in $.operatorArray) {
				if (operatorStr.toLowerCase() == oprtr.appelation.toLowerCase()) {
					operatorObj = oprtr
					break;
				}
			}

			if (operatorObj == null) {
				return -1; //could not match the operator
			}

			//assuming you were able to match the operator, calculate a time to return
			var rslt: Number = 1.0;
			var labelUse: String = operatorObj.labelUse;
			if (labelUse == null) labelUse = "";

			//if the custom time exists, use it, otherwise look up the time in the operators arrays
			if (customTime != "") {
				var parts: Array = customTime.split(' ');
				if (StringUtils.trim(parts[1]) == "ms" || StringUtils.trim(parts[1]) == "milliseconds") {
					return Number(parts[0]);
				} else if (StringUtils.trim(parts[1]) == "seconds") {
					return Number(parts[0] * 1000);
				} else if (StringUtils.trim(parts[1]) == "syllables") {
					rslt = Number(parts[0] / 2); //syllable time should be half of whole word time, which is used for op.time
				}
			} else if (operatorStr == "say" || operatorStr == "hear" || labelUse.indexOf("count_label_words") > -1) { //if there's no customTime, use the number of words in the lbl
				rslt = removeConsectiveWhiteSpaces(lbl).split(' ').length;
			} else if (operatorStr == "type" || labelUse.indexOf("count_label_characters") > -1) {
				var leftAngleBracketIndices: Array = lbl.match(/</g);
				var rightAngleBracketIndices: Array = lbl.match(/>/g);
				//because brackets are used for chunk naming, that should be removed from the lable length count if used in something like a Type operator
				if (leftAngleBracketIndices.length == rightAngleBracketIndices.length) rslt = lbl.length - leftAngleBracketIndices.length - rightAngleBracketIndices.length;
				else rslt = lbl.length; //if the operator is "type", figure out how many characters are in the string and save that as result
			}

			return Number(operatorObj.time) * rslt;
		}


		private static function removeConsectiveWhiteSpaces(lbl): String {
			while (lbl.search('  ') > -1) lbl = lbl.split('  ').join(' ');
			return lbl;
		}

		private static function getOperatorResource(operator: String): String {
			//if the custom exists, use it, otherwise look up the time in the operators arrays
			for each(var op in $.operatorArray) {
				if (operator.toLowerCase() == op.appelation.toLowerCase()) {
					return op.resource.toLowerCase();
				}
			}
			trace("no match resource for "+operator);
			return "no match"; //could not find a match
		}


		private static function removeComments(commentedStr: String): String {
			//remove any comments from the line - they'll be ignored
			var index: int = commentedStr.indexOf("*");
			var noComment: String;

			if (index >= 0) noComment = commentedStr.substring(0, index);
			else noComment = commentedStr;

			return noComment;
		}

		//Purpose: removes spaces and periods from front of line so that we can identify the operator
		//Input: String: raw line 
		//	Example: "...CreateState goal_name value"
		//Output: String: trimmed line 
		//	Example: "CreateState goal_name value"
		private static function trimIndents(line: String): String {
			while (line.length > 0 && line.charAt(0) == ' ' || line.charAt(0) == '.') {
				line = line.substr(1);
			}
			return line;
		}

		//Purpose: finds the lineNumbers of all goals in the program
		//Input: None
		//Output: Dictionary of goals and lines in the form: 
		//		key: goal_name
		//		value: lineNumber
		//Notes: Does not enforce scope
		//		 Goal line assumed to be in the form "...Goal: goal_name"
		private static function indexGoalLines(lines: Array): Dictionary {
			var goalIndexesByName = new Dictionary(); //key = goal_name, val=index
			for (var i = 0; i < lines.length; i++) {
				var frontTrimmedLine: String = trimIndents(lines[i]);
				var tokens: Array = frontTrimmedLine.split(' ');
				if (tokens[0].toLowerCase() == "goal:") {
					//Goal line assumed to be in the form "Goal: goal_name"
					var goalName = frontTrimmedLine.substring(6, frontTrimmedLine.length);
					goalIndexesByName[goalName] = i;
				}
			}
			return goalIndexesByName;
		}

		
		//Purpose: Finds next value of lineCounter. 
		//Input: Int lineCounter: lineNumber of Current If-statement
		//Output: int: the lineNumber of the next statement to be processed
		//	ifTrue: lineCounter - continue processing where you are.
		//	ifFalse: the line of the matching EndIf;
		private static function nextIfLine(lineCounter: int): int {
			var lines: Array = $.codeTxt.text.split("\r");
			var ifIsTrue: Boolean = evaluateIfStatement(trimIndents(lines[lineCounter]));
			if (ifIsTrue) {
				//do not jump any lines, lineCounter in parseloop will iterate to next line
				return lineCounter;
			} else {
				//Jump to the end of the ifStatement
				return findMatchingEndIf(lines, lineCounter);
			}
		}


		//Purpose: Returns the lineNumber of the matching EndIf
		//Input: Int lineCounter, the lineNumber of the current if statement
		//Output: int of the matching EndIf
		//		  if no ENDIF is found, returns end of program
		//Notes: Should handle nested ifs (fingers crossed)  
		//		 This method only runs when lines are to be skipped.
		//		 However, lines should still be colorized, so solarizeLine is called regardless
		private static function findMatchingEndIf(lines: Array, lineCounter: int): int {
			var numIfs: int = 1;
			var numEndIfs: int = 0;
			for (var i = lineCounter; i < lines.length; i++) {
				//SyntaxColor.solarizeLine(i);
				var frontTrimmedLine: String = trimIndents(lines[i]);
				var tokens: Array = frontTrimmedLine.split(' ');
				if (tokens[0] == "if") { //Handles nested ifs
					numIfs++; //for each if found, it must find an additional endif
				} else if (tokens[0] == "endif") {
					numEndIfs++;
					if (numEndIfs == numIfs) {
						trace("match endif line "+i);
						return i;
					}
				}
			}
			return lines.length;
		}

		private static function findFirstEndIf(lineCounter: int): int {
			var lines: Array = $.codeTxt.text.split("\r");
			for (var i = lineCounter; i < lines.length; i++) {
				//SyntaxColor.solarizeLine(i);
				var frontTrimmedLine: String = trimIndents(lines[i]);
				var tokens: Array = frontTrimmedLine.split(' ');
				if (tokens[0] == "endif") {
					trace("match endif line "+i);
					return i;
				}
			}
			return lines.length;
		}


		//Purpose: Checks the truth value of the input against the statetable
		//Input: String ifLine: already frontTrimmed line (If this_state isTrue)
		//Output: Boolean: if an entry in StateTable matches exactly the key and value
		//
		//Hint: if debugging, check that whitespace characters have been trimmed
		//in both the table and the input
		private static function evaluateIfStatement(ifLine: String): Boolean {
			//input must be in the form "If key value"
			var key: String = ifLine.split(' ')[1];
			var ifValue: String = ifLine.split(' ')[2];
			var tableValueString = $.stateTable[key];
			trace("comparing "+tableValueString+" vs "+ifValue);
			return (tableValueString === ifValue);
		}
		
	}
}
