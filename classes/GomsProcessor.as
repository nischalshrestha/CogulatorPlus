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

		private static var newThreadNumber: int; // = 0; //used as a thread name for "Also" when one is not provided

		private static var maxEndTime: Number; // = 0;
		private static var cycleTime: Number;

		public static var stackOverflow: Boolean = false;
		public static var errorsExist: Boolean = false;

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
			for (var key: Object in $.goalTable) delete $.goalTable[key]; // clear out all $.goalTable
			$.ifStack = []; // clear out the $.ifStack

			SyntaxColor.typing = false; // this lets SyntaxColor know that the model was refreshed
			trace("generate");
			generateStepsArray();

			if (steps.length > 0) processStepsArray(); //processes and then interleaves steps			

			return (new Array(maxEndTime, thrdOrdr, threadAvailability, intersteps, allmthds, cntrlmthds));
		}


		private static function generateStepsArray() {
			var errors:int = 0;
			var codeLines: Array = $.codeTxt.text.split("\r");
			var beginIndex: int = 0;
			var endIndex: int = codeLines[0].length;	
			for (var lineIndex: int = 0; lineIndex < codeLines.length; lineIndex++) {
				var line = codeLines[lineIndex];
				endIndex = beginIndex + line.length;
				if (StringUtils.trim(line) != "") {
					var syntaxArray:Array = SyntaxColor.solarizeLineNum(lineIndex, beginIndex, endIndex);

					var indentCount:int 	= syntaxArray[0];
					var stepOperator:String = syntaxArray[1];
					var stepLabel:String 	= trimLabel(syntaxArray[2]);
					var stepTime:String 	= syntaxArray[3];
					var chunkNames:Array 	= syntaxArray[7];

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
						steps.push(s); 
					} else {
						errors++;
					}
				}
				beginIndex = endIndex + 1;
			}
			var lines:Array = $.codeTxt.text.split("\r");

			// The goto steps need to be evaluated first since it requires all the steps
			// including the goal steps.
			//trace("errors "+errors);
			if (errors == 0) {
				evaluateGotoSteps();
			}
			removeGoalSteps();
			removeBranchSteps();
			setPrevLineNo();

		}

		private static function removeGoalSteps() {
			for (var i: int = steps.length - 1; i > -1; i--) {
				if (steps[i].operator == "goal" || steps[i].operator == "also") steps.splice(i, 1);
			}
		}

		// Purpose: Removes all steps that are within if blocks that were false, as well as the
		//			branch operator steps: If, CreateState, SetState, Endif, Goto.
		// Input: none
		// Output: none
		// SideEffect: removes items from the steps Array as needed
		private static function removeBranchSteps() {
			var unevaluatedLines:Array = SyntaxColor.getUnevaluatedSteps();
			var endifIndex:int = 0;
			for (var i:int = steps.length - 1; i > -1; i--) {
				var branchStep: int = SyntaxColor.branches.indexOf(steps[i].operator);
				if (unevaluatedLines.indexOf(steps[i].lineNo) != -1) {
					steps.splice(i, 1);	
				} else if (branchStep != -1) {
					steps.splice(i, 1);	
				}
			}
		}

		// Purpose: Evaluates goto steps to either inline or remove steps for loops and jumps respectively
		// Input: none
		// Output: none
		// SideEffect: Inserts and removes items from the steps Array as needed
		public static function evaluateGotoSteps(): void {
			var inlineIndex:int = 0;
			for (var i:int = 0; i < steps.length; i++) {
				var step:Step = steps[i];
				if (step.operator == "goto") {
					// This is for counting empty lines
					var emptyLines:int = 0;
					var gotoIndex:int = i;
					var goalIndex:int = -1;
					var goalEndIndex:int = -1;
					for (var j:int = 0; j < steps.length; j++) {
						if (steps[j].lineNo == $.goalTable[step.label].lineNo) {
							goalIndex = j;
						}	
						if (steps[j].lineNo == $.goalTable[step.label].end) {
							goalEndIndex = j;
						}
					}
					// if the goto forms a loop get inline steps for the loop and insert them
					if (goalIndex < gotoIndex) {
						// Because steps array will skip empty lines and hence line numbers, we need to consider 
						// any possible spaces between the first step and the gotoline as this will affect the 
						// way the inlining.
						if (goalIndex != -1 && steps[goalIndex+1] != undefined) {
							// Get number of spaces between goal and goto
							emptyLines = countEmptyLines(goalIndex, goalEndIndex);
						}
						stackOverflow = false;
						var inlineSteps:Array = SyntaxColor.getInlineSteps(gotoIndex, goalIndex, steps);
						// SyntaxColor will set this if there was an infinite loop while evaluating
						if (stackOverflow) {
							$.errors[steps[gotoIndex].lineNo] = "I ran into an infinite loop. Make sure this loop terminates.";
							break;
						} 
						// This replaces the current element with the next
						if (steps[i+1] != undefined) {
							var newStep:Step = steps[i+1].clone();
							newStep.lineNo = steps[i].lineNo;
							steps.splice(i, 1, newStep);
						} 
						for (var j:int = inlineSteps.length - 1; j > -1; j--) {
							steps.insertAt(gotoIndex, inlineSteps[j]);
						}
						// Update the index pointer so we resume processing at the right spot
						if (inlineSteps.length > 0){
							inlineIndex = i;
							i = i + inlineSteps.length;
						}
						// The index from which we started inlining
						var afterInlineIndex:int = i-1;
						// The offset for the remainder of steps has to be the total number of new items plus emptylines
						var toIncrement:int = steps[afterInlineIndex].lineNo + emptyLines;
						// If there were inlined steps inserted, make sure to update lineNos on any remaining steps 
						for (var j:int = afterInlineIndex; j < steps.length; j++, toIncrement++) {
							steps[j].lineNo = toIncrement;
						}
					} else if (goalIndex > gotoIndex) {
						// if it's a jump simply cut everything from goto line to goal
						// Note: As it stands there is no notion of returning from original goal.
						//		 Once a jump has been made the model will run from there onwards.
						steps.splice(i, (goalIndex - gotoIndex));
					}
				}
			}	
		}

		// Purpose: Counts up any empty lines between two line indices
		// Input: optional start and end indices to look at empty lines in a range
		// Output: an int representing the count of empty lines in the range or whole model
		// SideEffect: None
		private static function countEmptyLines(start: int = int.MIN_VALUE, end: int = int.MAX_VALUE): int {
			if (steps.length <= 1) return 0;
			var count:int = 0;
			var previous:int = steps[start].lineNo;
			for (var i:int = start+1; i <= end; i++) {
				var step:Step = steps[i];
				var difference:int = step.lineNo - previous;
				if (difference > 1) {
					count = count + (difference - 1);
				}
				previous = step.lineNo;
			}
			return count;
		}

		// Convenience function to print steps and their lineNos
		public static function printSteps(): void {
			for (var j:int = 0; j < steps.length; j++) {
				trace("FINAL "+j+" "+steps[j].operator+" "+steps[j].lineNo);
			}
		}

		private static function setPrevLineNo() {
			//steps[0] is set to 0 by default, all others should be updated
			for (var i: int = 1; i < steps.length; i++) {
				steps[i].prevLineNo = steps[i - 1].lineNo - 1;
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
					//trace("step and thread "+step.operator + ", "+step.thred);
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
		
	}
}
