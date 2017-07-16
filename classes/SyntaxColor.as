/*******************************************************************************
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
	import flash.text.TextFormat;
	import classes.WrappedLineUtils;
	import classes.SolarizedPalette;
	import com.inruntime.utils.*;
	
	public class SyntaxColor {
		private static var $:Global = Global.getInstance();
		private static var indents:int;
		private static var goalLine:Boolean;
		private static var branchLine:Boolean;
		private static var operator:String;
		private static var lineLabel:String;
		private static var time:String;
		private static var threadLabel:String;
		private static var errorFixed:Boolean;
		private static var chunkNames:Array = [];
		
		private static const black:TextFormat = new TextFormat();
		private static const grey:TextFormat = new TextFormat();
		private static const blue:TextFormat = new TextFormat();
		private static const cyan:TextFormat = new TextFormat();
		private static const orange:TextFormat = new TextFormat();
		private static const green:TextFormat = new TextFormat();
		private static const red:TextFormat = new TextFormat();
		private static const magenta:TextFormat = new TextFormat();
		private static const errorred:TextFormat = new TextFormat();
		
		static var methods:Array = ["goal", "also", "as"];
		static var branches:Array = ["if", "endif", "goto", "createstate", "setstate"];
		static var errorInLine:Boolean = false;

		static var typing:Boolean = false;
		private static var MAX_JUMPS: int = 20;

		black.color = SolarizedPalette.black;
		cyan.color = SolarizedPalette.cyan;
		grey.color = SolarizedPalette.grey;
		blue.color = SolarizedPalette.blue;
		orange.color = SolarizedPalette.orange;
		green.color = SolarizedPalette.green;
		red.color = SolarizedPalette.red;
		magenta.color = SolarizedPalette.magenta;
		errorred.color = SolarizedPalette.errorred;
		
		public static function solarizeAll():void{
			var codeLines:Array = $.codeTxt.text.split("\r");
			var beginIndex:int = 0;
			var endIndex:int = codeLines[0].length;
			for (var key:Object in $.errors) delete $.errors[key];  //clear out all $.errors

			for (var lineIndex:int = 0; lineIndex < codeLines.length; lineIndex++ ) {	
				var line = codeLines[lineIndex];
				endIndex = beginIndex + line.length;
				if (trim(line) != "") solarizeLineNum(lineIndex, beginIndex, endIndex);
				beginIndex = endIndex + 1;
			}
		}
		
		public static function solarizeSelectedLine():Boolean {
			typing = true;
			//get line number based on caret position
			var lineNumber = WrappedLineUtils.getLineNumber($.codeTxt, $.codeTxt.caretIndex);
				lineNumber--;
			var begindex = WrappedLineUtils.getLineIndex($.codeTxt, lineNumber);
			var endex = WrappedLineUtils.getLineEndIndex($.codeTxt, lineNumber);
			
			//chunkErrors are a special case because they can't be identified until after the GomsProcessor initiates WM modeling
			//chunkErrors are identified in WorkingMemory.as, which calls a custom function here (solarizeChunkAtLineNum) to color the errors
			var chunkNamedInError:String = "";
			var errMessage = $.errors[lineNumber];
			if (errMessage != undefined) if (errMessage.indexOf("memory") > -1) {
				var leftAngleIndex = errMessage.indexOf("<");
				var rightAngleIndex = errMessage.indexOf(">");
				chunkNamedInError = errMessage.substring(leftAngleIndex, rightAngleIndex);	
			}	
			
			return (solarizeLineNum(lineNumber, begindex, endex, chunkNamedInError)[6]);
		}
			
		//0: Number of Indents
		//1: Operator
		//2: Label
		//3: Custom Time (if used)
		//4: Thread Label
		//5: Error in line boolean
		//6: Error fixed in line boolean - the one non-Goms processor calls are looking for
		//7: Array of chunk names "<>"
		public static function solarizeLineNum(lineNum:int, beginIndex:int = -1, endIndex:int = -1, chunkNamedInError:String = ""):Array {

			time = "";
			chunkNames.length = 0;
			
			var lineIsInErrors:Boolean = false;
			if ($.errors[lineNum] != undefined) lineIsInErrors = true;
			errorInLine = false;
			
			if(beginIndex == -1) {
				beginIndex = findBeginIndex();
				endIndex = findEndIndex(beginIndex);
			}
			
			var index:int;
			var lineStartIndex:int = beginIndex;
			
			var lineTxt:String = $.codeTxt.text.substring(beginIndex, endIndex);
			if (chunkNamedInError == "") delete $.errors[lineNum];

			//     -start by setting the whole line to grey
			if (beginIndex > -1 && endIndex <= $.codeTxt.length) $.codeTxt.setTextFormat(grey, beginIndex, endIndex);
			
			//    -evaluate comments
			index = lineTxt.indexOf("*");
			if (index >= 0) {
				lineTxt = lineTxt.substring(0, index); //remove comments from what you're evaluating
			}
			
			indents = 0;
			if (trim(lineTxt) != "") {			
				//    -evaluate indents
				
				for (var d:int = 1; d < lineTxt.length; d++) {
					if (lineTxt.charAt(d) != "." && lineTxt.charAt(d) != " ") break;
				}
				
				indents = lineTxt.substring(0, d).split(".").length;
				$.codeTxt.setTextFormat(black, beginIndex + 0, beginIndex + d);
				
				
				//    -evaluate whether operator line or method control line
				index = findIndentEnd(lineTxt);
				endIndex = findItemEnd(index, lineTxt);
				if (endIndex != 0) {
						operator = lineTxt.substring(index, endIndex).toLowerCase();
						operator = trim(operator);
						goalLine = false;
						branchLine = false;
					for each (var method in methods) {
						if ( operator == method  ) {
							goalLine = true;
							break;
						} else if (operator.substring(0,operator.length - 1) == method) { 
							operator = operator.substring(0,operator.length - 1); // get rid of colon
							goalLine = true;
							break;
						}
					}
					// check if it's a branch for Cog+
					for each (var branch in branches) {
						if ( operator == branch  ) {
							branchLine = true;
							break;
						} else if (operator.substring(0,operator.length - 1) == branch) { 
							operator = operator.substring(0, operator.length - 1); // get rid of colon
							branchLine = true;
							break;
						}
					}
					// index is the operator, endIndex the item after operator
					if (branchLine) {
						solarizeBranchLine(lineTxt, index, lineNum, beginIndex, endIndex, lineStartIndex);
					} else if (goalLine) {
						solarizeGoalLine(lineTxt, index, lineNum, beginIndex, endIndex, lineStartIndex);
					} else {
						solarizeOperatorLine(lineTxt, index, lineNum, beginIndex, endIndex, lineStartIndex, chunkNamedInError);
					}
				}
			} else return new Array(0, "goal", "", "", "", false, false, []); //returning true here means it won't be included in the interleaving process if it's a comment
					
			if (errorInLine == false && lineIsInErrors == true) errorFixed = true; //true means an error was fixed
			else errorFixed = false;
						
			return new Array(indents, operator, lineLabel, time, threadLabel, errorInLine, errorFixed, chunkNames);
		}
		
		//If WM detects an error in chunk usage, this line is called to highlight the offending chunk(s)
		public static function solarizeChunkOnLineNum(lineNum:int, chunkName:String):void {
			var beginIndex = WrappedLineUtils.getLineIndex($.codeTxt, lineNum);
			var endIndex = WrappedLineUtils.getLineEndIndex($.codeTxt, lineNum);
			var lineTxt:String = $.codeTxt.text.substring(beginIndex, endIndex);
			
			chunkName = "<" + chunkName + ">";
			var chunkStartIndex = lineTxt.indexOf(chunkName);
			var chunkEndIndex = chunkStartIndex + chunkName.length;
			
			$.codeTxt.setTextFormat(errorred, beginIndex + chunkStartIndex + 1, beginIndex + chunkEndIndex - 1);
		}

		private static function solarizeBranchLine(lineTxt:String, index:int, lineNum:int, beginIndex:int, endIndex:int, lineStartIndex:int):void {
			lineLabel = "";
			time = "";
			threadLabel = "";

			// first color it magenta just like the methods
			$.codeTxt.setTextFormat(magenta, beginIndex + index, beginIndex + endIndex);
			// then evaluate what the operator is error handle based on the type of operator
			index = findNextItem(endIndex, lineTxt); 
			endIndex = (beginIndex + lineTxt.length);

			var tokens: Array = lineTxt.split(' ');
			switch (operator) {
				case "createstate":
					if (hasError(tokens, lineNum)) {
						$.codeTxt.setTextFormat(errorred, beginIndex, endIndex);
					} else {
						createState(lineNum, tokens[1], tokens[2]);
						$.codeTxt.setTextFormat(black, beginIndex + index, endIndex);
					}
					break;
				case "setstate":
					if (hasError(tokens, lineNum)) {
						$.codeTxt.setTextFormat(errorred, beginIndex, endIndex);
					} else {
						setState(lineNum, tokens);
						$.codeTxt.setTextFormat(black, beginIndex + index, endIndex);
					}
					break;
				case "if":
					if (hasError(tokens, lineNum)) {
						//ErrorColorLine(lineNum);
						$.codeTxt.setTextFormat(errorred, beginIndex, endIndex);
					} else {
						//should return int of next line to be processed based on the resolution
						//of the if statement.
						$.codeTxt.setTextFormat(black, beginIndex + index, endIndex);
					}
					break;
				case "endif":
					if (hasError(tokens, lineNum)) {
						$.codeTxt.setTextFormat(errorred, beginIndex, endIndex);
					} else if (endIndex < lineTxt.length) {
						$.codeTxt.setTextFormat(magenta, beginIndex + index, endIndex);
					}
					//ignore EndIfs, but are useful in processing original statement.
					break;
				case "goto":
					if (hasError(tokens, lineNum)) {
						$.codeTxt.setTextFormat(errorred, beginIndex, endIndex);
					} else {
						$.codeTxt.setTextFormat(black, beginIndex + index, endIndex);
					}
					break;
			}

		}

		//Filter Method to get rid of empty strings in token array.  Taken from example
		//http://board.flashkit.com/board/showthread.php?805338-Remove-empty-elements-in-an-arry
		private static function noEmpty(item: * , index: int, array: Array): Boolean {
			return item != "";
		}

		// Purpose:  To determine if there is a syntax error in added operators
		// Input: front trimmed line tokenized using space as dilimiter. 
		//		  Operator should always be first token
		//        Example:  CreateState,target1,isFriendly,,,  <-whitespace at end of line
		//		  Example:  GoTo,Goal:,hands,and,feet
		// Output: Boolean 
		//		   True if hasError.
		//		   False if syntax is correct
		//
		// Notes: Does not handle infinite loops or invalid GoTo jumps.  Those are handled in
		//		  GenerateStepsArray when GoTo is processed.
		private static function hasError(tokens: Array, lineNum:int): Boolean {
			//Gets rid of empty tokens caused by whitespace
			tokens = tokens.filter(noEmpty);
			var lines:Array = $.codeTxt.text.split("\r");
			if (operator == "createstate") {
				//CreateState name value extraStuff
				//CreateState name
				//Name already exists
				if (tokens.length != 3) {
					errorInLine = true;
					$.errors[lineNum] = "I was expecting 2 arguments."
					return true;
				} else if ($.stateTable[tokens[1]] !== undefined && !typing) {
					errorInLine = true;
					$.errors[lineNum] = "'"+tokens[1]+"' already exists."
					return true;
				}
			} else if (operator == "setstate") {
				if(!(tokens.length == 3 || tokens.length == 4)){
					errorInLine = true;
					$.errors[lineNum] = "I was expecting 2 or 3 arguments."
					return true;
				} else if($.stateTable[tokens[1]] == undefined){
					errorInLine = true;
					$.errors[lineNum] = "'"+tokens[1]+"' does not exist."
					return true;
				} else if(tokens.length == 4){
					//Make sure the last field is a number between 0 and 1 inclusive on both sides.
					if(isNaN(tokens[3])){
						//trace("NaN: " + tokens[3] + " " + isNaN(tokens[4]));
						errorInLine = true;
						$.errors[lineNum] = "3rd argument should be a number between 0 and 1, but I got '"+tokens[3]+"'"
						return true;
					} else {
						var prob = Number(tokens[3]);
						if(!(0<= prob && prob <= 1)){
							errorInLine = true;
							$.errors[lineNum] = "Probability number should be between 0 and 1"
							return true;
						}
					}
				}
			} else if (operator == "if") {
				if (tokens.length != 3) {
					errorInLine = true;
					$.errors[lineNum] = "I was expecting 2 arguments."
					return true;
				} else if ($.stateTable[tokens[1]] == undefined){
					errorInLine = true;
					$.errors[lineNum] = "'"+tokens[1]+"' does not exist."
					return true;
				} else {
					// Check if it's missing an endif
					if (findMatchingEndIf(lines, lineNum) == lines.length) {
						errorInLine = true;
						$.errors[lineNum] = "I was expecting an EndIf."
						return true;
					}
				}
			} else if (operator == "endif") {
				if (tokens.length != 1 && !typing) {
					errorInLine = true;
					$.errors[lineNum] = "I was not expecting any arguments."
					return true;
				}
			} else if (operator == "goto") {
				if (tokens.length <= 2) {
					errorInLine = true;
					$.errors[lineNum] = "I was expecting 2 arguments."
					return true;
				}
				if (clean(tokens.slice(0, 2).join(" ").toLowerCase()) != "goto goal") {
					//trace("cleaned up goto "+clean(tokens.slice(0, 2).join(" ").toLowerCase()));
					errorInLine = true;
					$.errors[lineNum] = "I was expecting something like 'goto goal'."
					return true;
				}
				// Index all goals defined and check if goal exists
				indexGoalLines(lines);
				var goalLabel: String = tokens.slice(2, tokens.length).join(" ").toLowerCase();
				var goalLine = $.goalTable[goalLabel];
				if (goalLine == undefined) {
					errorInLine = true;
					$.errors[lineNum] = "'"+goalLabel+"' does not exist."
					return true;
				}
				lineLabel = goalLabel;
			}
			errorInLine = false;
			return false;
		}

		// Creates all the inline steps necessary for a goto loop so GomsProcessor can prepare its steps Array
		public static function getInlineSteps(gotoIndex: int, goalIndex: int, goalObject: Object, steps: Array): Array {
			// Check if it the goto can even be executed the first time through
			var gotoLine:int = steps[gotoIndex].lineNo;
			var withinIfIndex:int = withinIfBlock(gotoLine);
			if (withinIfIndex != -1) {
				var unevaluatedLines:Array = getUnevaluatedSteps();
				var gotoExcluded:Boolean = unevaluatedLines.indexOf(gotoLine) != -1;
				if (gotoExcluded) return [];
			}
			// Grab the relevant goals
			var goalSteps:Array = steps.slice(goalIndex, gotoIndex+1);
			// Prepare a final array
			var finalGoalSteps:Array = new Array();
			// This offset is for creating fake lists to determine new line numbers for subsequent
			// iterations of the loop
			var offset:int = goalObject.end - goalObject.lineNo;
			// The goto line shifts when inlining so it will be updated in the process
			var currentGotoLine:int = gotoLine;
			var iter:int = 1;
			var breakout:Boolean = false;
			while (!breakout) {
				// This temporary Array will hold the new inline steps
				var newGoalSteps:Array = new Array();
				for (var i:int = 0; i < goalSteps.length; i++) {
					var step:Step = goalSteps[i];
					var newLineNo:int = step.lineNo + offset*iter;
					var newStep:Step = step.clone();
					newStep.lineNo = newLineNo;
					newGoalSteps.push(newStep);
					finalGoalSteps.push(newStep);
				}
				// Make changes to the $.ifStack and the $.stateTable according to new inline steps
				addInlineStateChanges(goalSteps, offset*iter);
				// Evaluate the new goal steps from the initial starting point to the new ending point,
				// which is where we should be after the new inline steps were added
				var unevaluatedLines:Array = getUnevaluatedSteps(goalObject.start, (currentGotoLine+offset*iter));
				// Check whether the goto line was excluded, if so we break out of the inlining process
				for (var i:int = 0; i < finalGoalSteps.length; i++) {
					var step:Step = finalGoalSteps[i];
					if (step.operator == "goto") {
						var gotoExcluded:Boolean = unevaluatedLines.indexOf(step.lineNo) != -1;
						if (gotoExcluded) breakout = true;
					} 
				}
				iter++;
				trace("iter "+iter);
				// Check for infinite loops, there is an arbitrary limit of 20 jumps currently
				if (iter >= MAX_JUMPS) {
					// Let GomsProcessor know there has been an infinite loop
					GomsProcessor.stackOverflow = true;
					break;
				}
				// Update goto line with a new offset
				currentGotoLine = currentGotoLine + offset*iter;
			}
			return finalGoalSteps;
		}

		// updates the state table with new inlined steps for goto loops
		// takes in the relevant goal steps and an offset to update lineNos for new entries
		public static function addInlineStateChanges(goalSteps: Array, offset: int): void {
			for (var i:int = 0; i < goalSteps.length; i++) {
				var step:Step = goalSteps[i];
				// Add 'new' if blocks with updated if and endif lines and reset truth
				if (step.operator == "if") {
					var ifBlock:Object = findIfBlock(step.lineNo);
					var newIfBlock:Object = new Object();
					newIfBlock.ifLine = ifBlock.ifLine + offset;
					newIfBlock.key = ifBlock.key;
					newIfBlock.value = ifBlock.value;
					newIfBlock.truth = true;
					newIfBlock.endIfLine = ifBlock.endIfLine + offset;
					$.ifStack.push(newIfBlock);
				}
				// Add new createstate/setstate objects
				if (step.operator == "createstate" || step.operator == "setstate") {
					var stateChange:Object = findStateChangeIndex(step.lineNo);
					var newStateChange:Object = new Object();
					newStateChange.lineNo = stateChange.lineNo + offset;
					newStateChange.key = stateChange.key;
					newStateChange.value = stateChange.value;
					newStateChange.valid = true;
					$.stateTable[stateChange.key].push(newStateChange);
				}						
			}
		}

		// Convenience function for debugging if stack
		public static function printIfBlocks(): void {
			for (var i = 0; i < $.ifStack.length; i++) {
				var ifBlock:Object = $.ifStack[i];
				trace(ifBlock.ifLine + " if " + ifBlock.key + " " + ifBlock.value);
			}
		}

		// Convenience function for debugging state table
		public static function printStateTable(): void {
			for (var key: Object in $.stateTable) {
				var scopeList:Array = $.stateTable[key];
				for (var i = 0; i < scopeList.length; i++) {
					var stateChange:Object = scopeList[i];
					trace(stateChange.lineNo+" state change "+stateChange.key + " "+stateChange.value);
				}
			}
		}

		// Returns the ifBlock Object given the ifLine
		public static function findIfBlock(ifLine: int): Object {
			for (var i = 0; i < $.ifStack.length; i++) {
				if ($.ifStack[i].ifLine == ifLine) {
					return $.ifStack[i];
				}
			}
			return null;
		}

		// Returns the createstate/setstate Object given the ifLine
		public static function findStateChangeIndex(lineNo: int): Object {
			for (var key: Object in $.stateTable) {
				var scopeList:Array = $.stateTable[key]; // clear out all $.stateTable
				for (var i = 0; i < scopeList.length; i++) {
					//trace("sc No: "+scopeList[i].lineNo);
					if (scopeList[i].lineNo == lineNo) {
						return scopeList[i];
					}
				}
			}
			return null;
		}

		// Purpose: Evaluate all if blocks in $.ifStack and return an Array of line numbers to remove
		// Input: none
		// Output: Array holding all the line numbers for steps the GomsProcessor will remove
		// SideEffect: changes truth value of if blocks and possibly valid attribute of state objects
		public static function getUnevaluatedSteps(start: int = int.MIN_VALUE, end: int = int.MAX_VALUE): Array {
			var unevaluatedLines:Array = new Array();
			for (var i = 0; i < $.ifStack.length; i++) {
				var ifBlock:Object = $.ifStack[i];
				if (ifBlock.ifLine >= start && ifBlock.ifLine <= end) {
					// check if the current if block is within another if block
					var parentIfIndex:int = withinIfBlock(ifBlock.ifLine);
					var parentIfBlock:Object;
					if (parentIfIndex != -1) {
						parentIfBlock = $.ifStack[parentIfIndex];
					}
					// if so, check if that parent if block is false
					if (parentIfBlock != null && !parentIfBlock.truth) {
						// if parent if block is false, we're done. 
						// invalidate the if line and add unevaluated lines
						gatherUnevaluatedLines(i, unevaluatedLines);
						// continue on to the next if block to evaluate
						continue;
					}
					// if you're here, it means current if block can be evaluated
					// grab the latest state change before this if block that's valid to check against
					var nextScope:Object = returnNextScope(ifBlock.ifLine, ifBlock.key);
					var evaluation:Boolean = evaluateIfStatement(nextScope.value, ifBlock.value);
					if (!evaluation) {
						// if current if block is within a parent if block that's false, add lines
						gatherUnevaluatedLines(i, unevaluatedLines);
					}
				}
			}
			return unevaluatedLines;
		}

		// Purpose: Make if block invalid and add all the unevualated lines to the passed in array
		// Input: int ifBlockIndex, the index of the if block in $.ifStack
		//		  Array unevaluatedLines, an array to hold all unevaluated line numbers
		// Output: none
		// SideEffect: adds lines to passed in array and can change the valid attribute of the state 
		// 			   objects within the if block
		public static function gatherUnevaluatedLines(ifBlockIndex: int, unevaluatedLines: Array): void {
			// if block is no longer valid
			$.ifStack[ifBlockIndex].truth = false; 
			for (var j = $.ifStack[ifBlockIndex].ifLine; j <= $.ifStack[ifBlockIndex].endIfLine; j++) {
				if (unevaluatedLines.indexOf(j)) unevaluatedLines.push(j);
			}
			// find any create state, state within this if block and set them to invalid
			invalidateStateChanges($.ifStack[ifBlockIndex].ifLine);
		}

		// Purpose: Invalidates all state changes made inside an if because it was false
		// Input: int ifLine, the line number of the if line
		// Output: none
		// SideEffect: can change the valid attribute of the state object
		public static function invalidateStateChanges(ifLine: int): void {
			for (var key: Object in $.stateTable) {
				var scopeList:Array = $.stateTable[key]; // clear out all $.stateTable
				for (var i = 0; i < scopeList.length; i++) {
					var parentIfIndex:int = withinIfBlock(scopeList[i].lineNo);
					if (parentIfIndex != -1) {
						var ifBlockIndex:int = $.ifStack[parentIfIndex].ifLine;
						if (ifBlockIndex === ifLine) {
							$.stateTable[key][i].valid = false;
						}
					}
				}
			}
		}

		// Purpose: Determines whether a line is within an if block or not
		// Input: int lineNo, the line number in question
		// Output: index of the if block in $.ifStack if line is within an if block
		//		   -1 if line is not within an if block
		// SideEffect: none
		public static function withinIfBlock(lineNo: int): int {
			for (var i = $.ifStack.length-1; i > -1; i--) {
			//	trace("ifstack if "+$.ifStack[i].ifLine + ", endif "+$.ifStack[i].endIfLine);
				if ($.ifStack[i].ifLine < lineNo && $.ifStack[i].endIfLine > lineNo) {	
					return i;
				}
			}
			return -1;
		}

		// Purpose: Returns the next valid state change object, representing a createstate/setstate declaration
		//			This method will start looking for the correct createstate/setstate line above the current
		//		    if condition, so that we test the condition against the latest createstate or setstate.
		//			It will also check whether it is the right createstate/setstate, e.g. not inside a false if
		//			via checking the valid attribute of the state object.
		// Input: int lineNo, line number of the if condition
		//		  String ifKey, the state the if condition is testing
		// Output: the correct if object if found, null otherwise
		// SideEffect: none
		public static function returnNextScope(lineNo: int, ifKey: String): Object {
			var scopeList:Array = $.stateTable[ifKey];
			for (var i = scopeList.length-1; i > -1; i--) {
				var scopeLine:int = scopeList[i].lineNo;
				if (scopeLine < lineNo && scopeList[i].valid) {
					return scopeList[i];
				}
			}
			return null;
		}

		// Purpose: Evaluates a given table value for a state and an if condition value
		// Input: String tableValue, representing the value of the state in the $.stateTable
		//		  String ifValue, the value the if condition is testing
		// Output: true if condition is true, false otherwise
		// SideEffect: none
		public static function evaluateIfStatement(tableValue: String, ifValue: String): Boolean {
			return (tableValue === ifValue);
		}

		// We might be able to remove this for checking infinite loops since we have $.ifStack
		// Purpose: Finds next value of lineCounter. 
		// Input: Array lines, the lines for the whole text in the editor
		//		  int lineNum, lineNumber of Current If-statement
		// Output: int: the lineNumber of the next statement to be processed
		// SideEffect: none
		public static function nextIfLine(lines: Array, lineNum: int):int {
			for (var i = lineNum; i < lines.length; i++) {
				var frontTrimmedLine: String = clean(lines[i].toLowerCase());
				var tokens: Array = frontTrimmedLine.split(' ');
				if (tokens[0].toLowerCase() == "if") {
					return i; // once the next if is found, return the index
				}
			}
			return -1;
		}

		// Purpose: Returns the lineNumber of the matching EndIf
		// Input: Array lines, representing all of the lines of the model
		//		  int lineNum, the lineNumber of the current if statement
		// Output: int of the matching EndIf
		//		   if no ENDIF is found, returns entire length of lines
		// Notes: Handles possible nested ifs
		// SideEffect: creates an If Object that represents an if block with:
		//			   ifLine, the line at which it is declared
		//			   key, the key it is testing
		//			   value, the value it is testing key against
		//			   truth, whether it is true or false (true by default initially)
		public static function findMatchingEndIf(lines: Array, lineNum: int): int {
			var numIfs: int = 0;
			var numEndIfs: int = 0;
			var ifIndices:Array = new Array();
			for (var i = lineNum; i < lines.length; i++) {
				var frontTrimmedLine: String = clean(lines[i].toLowerCase());
				var tokens: Array = frontTrimmedLine.split(' ');
				if (tokens[0] == "if") { //Handles nested ifs
					var ifObject:Object = new Object();
						ifObject.ifLine = i;
						ifObject.key = tokens[1];
						ifObject.value = tokens[2];
						ifObject.truth = true;
					//trace("pushing if on line "+i);
					ifIndices.push(ifObject);
					numIfs++; //for each if found, it must find an additional endif
				} else if (tokens[0] == "endif") {
					numEndIfs++;
					var ifObject = ifIndices.pop();
					//trace("poping if on line "+ifLine);
					if (numEndIfs == numIfs) {
						ifObject.endIfLine = i;
						$.ifStack.push(ifObject);
						return i;
					}
				}
			}
			return lines.length;
		}
		
		// Purpose: Creates a new state in the stateTable, where the value is an Array.
		// The Array holds a state Object that represents the declartion of that state
		// with its line number, key (statename), value and whether or not it is valid for
		// if conditions to check against.
		// Input:  String key, String value (target1, visited)
		// Output: none
		// SideEffect:  An new entry in global stateTable is added
		private static function createState(lineNo: int, key: String, value: String): void {
			var state:Object = new Object();
			state.lineNo = lineNo;
			state.key = key;
			state.value = value;
			state.valid = true;
			var scopeList:Array = new Array();
			scopeList.push(state);
			$.stateTable[key] = scopeList;
		}

		// Purpose: Changes an existing state in the stateTable by inserting a new state Object.
		// The new state Object represents the state declaration of that state with its line number,
		// key (statename), value and whether or not it is valid for if conditions to check against.
		// Input: lineNo of the SetState and a line Array that represents the current line in text in tokens
		// Two possible forms of the line:	
		// (Form) String if, String key, String value (target1, visited)  OR
		//		  String if, String key, String value (target1, visited), String probability (between 0 and 1) 
		// Output: none
		// SideEffect: An existing entry in global stateTable is changed
		private static function setState(lineNo: int, line: Array): void {
			var state:Object = new Object();
			state.lineNo = lineNo;
			state.key = clean(line[1]);
			state.value = line[2];
			state.valid = true;
			if(line.length == 3){
				// grab the scope list associated with the state and push the new scope in
				$.stateTable[line[1]].push(state);
			} else { //should have 4 tokens, SetState state_name value probability (number between 0-1) 
				var randomNumber:Number = Math.random();
				var givenProbability:Number = Number(line[3]);
				if(randomNumber < givenProbability){
					$.stateTable[line[1]].push(state);
					//trace("Successfully set: " + line[0] + " " + line[1] + " " + line[2] + " " + line[3]);
				} else {
					//trace("RandomNumber did not exceed threshold: " + line[0] + " " + line[1] + " " + line[2] + " " + line[3]);
				}
			}
		}


		// Purpose: finds the lineNumbers of all goals in the program and stores them in the $.goalTable
		// 			The value is an Object with attributes lineNo, start (start of actual steps), end
		// Input: Array of lines representing the text on the editor
		// Output: none
		// SideEffect: makes entries of all the goals in the model in $.goalTable
		// Notes: Does not enforce scope
		private static function indexGoalLines(lines: Array): void {
			var previousGoal:String = "";
			for (var i = 0; i < lines.length; i++) {
				var frontTrimmedLine: String = clean(lines[i]);
				var tokens: Array = frontTrimmedLine.split(' ');
				var operator: String = tokens[0].toLowerCase();
				if (operator == "goal") {
					// Goal line assumed to be in the form "goal goal_name"
					var goalName = frontTrimmedLine.toLowerCase().split("goal ")[1];
					var goalObject = new Object();
					goalObject.lineNo = i;
					goalObject.start = i+1;
					goalObject.end = lines.length;
					// Set the previous goal's end line for its scope
					if (previousGoal != "") {
						$.goalTable[previousGoal].end = goalObject.lineNo-1;
					}
					$.goalTable[goalName] = goalObject;
					previousGoal = goalName;
				}
			}
		}

		private static function solarizeGoalLine(lineTxt:String, index:int, lineNum:int, beginIndex:int, endIndex:int, lineStartIndex:int):void {
			$.codeTxt.setTextFormat(magenta, beginIndex + index, beginIndex + endIndex);
			
			//    -evaluate method name
			index = findNextItem(endIndex, lineTxt);
			endIndex = findLabelEnd(lineTxt, "as ");
			
			lineLabel = lineTxt.substring(index, endIndex);
			threadLabel = "base"; //set here, may be modified by also method below;
			if (lineLabel.length > 0) $.codeTxt.setTextFormat(black, beginIndex + index, beginIndex + endIndex);
			
			index = lineTxt.toLowerCase().indexOf("as ");
			endIndex = index + 3;
			if (operator == "also"){
				threadLabel = "!X!X!"; 
				if (index > -1) {// if "as" is used
					//set "as" magenta
					$.codeTxt.setTextFormat(magenta, beginIndex + index, beginIndex + endIndex);
					//determine thread name & color code
					index = findNextItem(endIndex, lineTxt);
					endIndex = index + lineTxt.length;
					threadLabel = lineTxt.substring(index, endIndex);
					if (threadLabel.length > 0) $.codeTxt.setTextFormat(black, beginIndex + index, beginIndex + index + threadLabel.length);
				}
			}
		}
		
		private static function solarizeOperatorLine(lineTxt:String, index:int, lineNum:int, beginIndex:int, endIndex:int, lineStartIndex:int, chunkNamedInError:String):void {
			threadLabel = "base"; //setting for the return array			
			
			//    -evaluate operator
			var match:Boolean = false;
			for each (var op in $.operatorArray) {
				if (operator == op.appelation.toLowerCase()) {
					match = true;
					break;
				}
			}
			if (operator.length > 0) {
				if (!match) {
					$.errors[lineNum] = "Couldn't find an operator.";
					$.codeTxt.setTextFormat(errorred, beginIndex + index, beginIndex + endIndex);
					errorInLine = true;
				} else $.codeTxt.setTextFormat(blue, beginIndex + index, beginIndex + endIndex);
			}
				
				
			//    -evaluate label
			index = findNextItem(endIndex, lineTxt);
			endIndex = findLabelEnd(lineTxt, "(");
			lineLabel = lineTxt.substring(index, endIndex);
			if (lineLabel.length > 0) $.codeTxt.setTextFormat(black, beginIndex + index, beginIndex + endIndex);
				
			
			//    -evaluate WM chunks
			var leftAngleBracketIndex:int = 0;
			var rightAngleBracketIndex:int = 0;
			var leftAngleBracketIndices:Array = lineTxt.match(/</g);
			var rightAngleBracketIndices:Array = lineTxt.match(/>/g);
			if (leftAngleBracketIndices != null && rightAngleBracketIndices != null) {
				for (var i:int = 0; i < leftAngleBracketIndices.length; i++) {					
					leftAngleBracketIndex = lineTxt.indexOf(leftAngleBracketIndices[i], leftAngleBracketIndex);
					rightAngleBracketIndex = leftAngleBracketIndex + 1;
					rightAngleBracketIndex = lineTxt.indexOf(rightAngleBracketIndices[i], rightAngleBracketIndex);
					var chunkName = lineTxt.substring(leftAngleBracketIndex, rightAngleBracketIndex);	
										
					if (rightAngleBracketIndex > leftAngleBracketIndex + 1) {
						if (chunkNamedInError != chunkName) $.codeTxt.setTextFormat(cyan, beginIndex + leftAngleBracketIndex + 1, beginIndex + rightAngleBracketIndex);
						else $.codeTxt.setTextFormat(errorred, beginIndex + leftAngleBracketIndex + 1, beginIndex + rightAngleBracketIndex);
						chunkNames.push(lineTxt.substring(leftAngleBracketIndex + 1, rightAngleBracketIndex));
					}
					
					leftAngleBracketIndex = rightAngleBracketIndex + 1;
					rightAngleBracketIndex = leftAngleBracketIndex + 1;
				}
			}
			
			
			//    -evaluate time
			time = "";
			var leftParenIndex:int = lineTxt.indexOf("(");
			var rightParenIndex:int = lineTxt.indexOf(")");
			if (leftParenIndex > -1) {
				$.codeTxt.setTextFormat(black, beginIndex + leftParenIndex, beginIndex + leftParenIndex + 1); //set right paren to black
				
				//if the "(" marker exists
				if (rightParenIndex > -1 && rightParenIndex > leftParenIndex) {  //if the ")" marker exists and occurs after the left marker					
					$.codeTxt.setTextFormat(black, beginIndex + rightParenIndex, beginIndex + rightParenIndex + 1); //set right paren to black
					
					//find what's in the number position
					index = findNextItem(leftParenIndex + 1, lineTxt);
					endIndex = findItemEnd(index, lineTxt);
					var timeValue:String = lineTxt.substring(index, endIndex);
						timeValue = trim(timeValue);
					if ( isNaN(Number(timeValue) )  ) {
						$.errors[lineNum] = "I was expecting a number after the left parenthesis.";
						if (String(timeValue).length > 0) {
							$.codeTxt.setTextFormat(errorred, beginIndex + index, beginIndex + endIndex);
							time = ""; //if there is an error, blank out time so you don't try to evaluate it GomsProcessor
							errorInLine = true;
						} 
					} else {
						time = String(timeValue);
						$.codeTxt.setTextFormat(black, beginIndex + index, beginIndex + endIndex);
					}

					//find what's in the units position
					index = findNextItem(endIndex, lineTxt);
					endIndex = findLabelEnd(lineTxt,")") + 1;
					var timeUnits:String = (lineTxt.substring(index, endIndex)).toLowerCase();
						timeUnits = trim(timeUnits);
					if (String(timeValue).length > 0) { //only continue with the evaluation if you have a number in the first position
						if (timeUnits != "syllables" && timeUnits != "seconds" && timeUnits != "milliseconds" && timeUnits != "ms") {
							$.errors[lineNum] = "The modifier can be 'seconds', 'milliseconds', or 'ms'";
							if (timeUnits.length > 0) { 
								$.codeTxt.setTextFormat(errorred, beginIndex + index, beginIndex + endIndex);
								time = ""; //if there is an error, blank out time so you don't try to evaluate it GomsProcessor
								errorInLine = true;
							} 
						} else  {
							time = time + " " + timeUnits;
							$.codeTxt.setTextFormat(green, beginIndex + index, beginIndex + endIndex); //set units to green
						}
					}
					
				} else if (rightParenIndex < leftParenIndex && rightParenIndex > - 1) { //if there is a right paren before the left paren
						$.errors[lineNum] = "I found a right paren before the left paren";
						time = ""; //if there is an error, blank out time so you don't try to evaluate it GomsProcessor
						errorInLine = true;
						$.codeTxt.setTextFormat(errorred, beginIndex + rightParenIndex, beginIndex + rightParenIndex + 1);
				} else { // if there is a left paren with no right paren...
					$.errors[lineNum] = "I was expecting a right parenthesis.";
					time = ""; //if there is an error, blank out time so you don't try to evaluate it GomsProcessor
					errorInLine = true;
					$.codeTxt.setTextFormat(errorred, beginIndex + leftParenIndex, beginIndex + lineTxt.length);
				}

			}
		
		}

		// Purpose: removes unnecessary characters (see trim), indents, and colons
		// Input: String: raw line 
		//	 	  Example: "...CreateState goal_name value"
		// Output: String: trimmed line 
		// Example: "CreateState goal_name value"
		public static function clean(s: String): String {
			return trimColon(trimIndents(trim(s))).toLowerCase();
		}
			
		private static function trim(s: String): String {
			return s.replace(/^[\s|\t|\n]+|[\s|\t|\n]+$/gs, '');
		}

		// Purpose: removes spaces and periods from front of line so that we can identify the operator
		// Input: String: raw line 
		//		  Example: "...CreateState goal_name value"
		// Output: String: trimmed line 
		//		   Example: "CreateState goal_name value"
		public static function trimIndents(line: String): String {
			while (line.length > 0 && line.charAt(0) == ' ' || line.charAt(0) == '.') {
				line = line.substr(1);
			}
			return line;
		}

		// Purpose: removes all colons from a string to make it be optional for parsing
		// Input: String: operator string
		//	Example: "CreateState: goal_name value"
		//  Output: String: trimmed operator 
		//	Example: "CreateState goal_name value"
		public static function trimColon(string: String): String {
			var trimmed:String = string;
			var colon:int = trimmed.indexOf(':');
			while (colon != -1) {
				trimmed = trimmed.substring(0, colon) + trimmed.substring(colon + 1, trimmed.length);
				colon = trimmed.indexOf(':');
			}
			return trimmed;
		}
		
		private static function countIdents(lineTxt:String):int {
			var indx:int = 0;
			indents = 0;
			while (lineTxt.charAt(indx) == " " || lineTxt.charAt(indx) == ".") {
				if (lineTxt.charAt(indx) == ".") indents++;
				indx++;
			}
			return indx++;
		}
		
		
		private static function findBeginIndex():int {
			var startPara:int = $.codeTxt.getFirstCharInParagraph($.codeTxt.getFirstCharInParagraph($.codeTxt.caretIndex));
			return startPara;
		}
		
		private static function findEndIndex(beginIndex:int):int {
			return ( beginIndex + $.codeTxt.getParagraphLength(beginIndex) );
		}
		
		
		private static function findLabelEnd(lineTxt:String, brkString:String):int {
			var endIndex:int = lineTxt.indexOf(brkString);
			if (endIndex == -1) endIndex = lineTxt.length;
			else endIndex--;
			
			return endIndex;
		}
		
		private static function findIndentEnd(lineTxt:String):int{
			for (var i:int = 0; i < lineTxt.length; i++){
				if (lineTxt.charAt(i) != " " && lineTxt.charAt(i) != ".") return i;
			}
			return lineTxt.length;
		}
		
		private static function findItemEnd(startIndex:int, lineTxt:String):int {
			var rslt:int = lineTxt.indexOf(" ", startIndex);
			if (rslt < 0) return lineTxt.length;
			else return rslt;
		}
		
		private static function findNextItem(startIndex:int, lineTxt:String):int {
			for (var i:int = startIndex; i < lineTxt.length; i++){
				//the && deals with consecutive delims
				//if (lineTxt.charAt(i) != " " && lineTxt.charAt(i - 1) == " ") return i;
				if (lineTxt.charAt(i) != " ") return i;
			}
			return lineTxt.length;
		}
		
	}
}
